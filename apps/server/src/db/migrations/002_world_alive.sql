PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   0) Small upgrades to existing characters (stats + carry)
   ========================================================= */

ALTER TABLE characters ADD COLUMN hp INTEGER NOT NULL DEFAULT 30;
ALTER TABLE characters ADD COLUMN hp_max INTEGER NOT NULL DEFAULT 30;

ALTER TABLE characters ADD COLUMN stamina INTEGER NOT NULL DEFAULT 30;
ALTER TABLE characters ADD COLUMN stamina_max INTEGER NOT NULL DEFAULT 30;

-- Encumbrance: big capacity so kids aren’t back-and-forth constantly.
ALTER TABLE characters ADD COLUMN carry_capacity REAL NOT NULL DEFAULT 120.0;


/* =========================================================
   1) Item catalog (definitions) vs owned items (instances)
   ========================================================= */

CREATE TABLE IF NOT EXISTS item_defs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,                        -- weapon/armor/trinket/consumable/resource/tool/quest/container/ammo/component
  slot TEXT NULL,
  rarity TEXT NOT NULL DEFAULT 'common',
  stackable INTEGER NOT NULL DEFAULT 0,
  max_stack INTEGER NOT NULL DEFAULT 1,
  base_value INTEGER NOT NULL DEFAULT 0,
  weight REAL NOT NULL DEFAULT 0.0,
  durability_max INTEGER NOT NULL DEFAULT 0, -- 0 => indestructible
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS item_instances (
  id TEXT PRIMARY KEY,
  item_def_id TEXT NOT NULL,
  owner_character_id TEXT NULL,
  location_type TEXT NOT NULL DEFAULT 'inventory', -- inventory/equipment/shop/container/world
  location_id TEXT NULL,
  qty INTEGER NOT NULL DEFAULT 1,
  durability INTEGER NOT NULL DEFAULT 0,
  quality INTEGER NOT NULL DEFAULT 0,
  rolls_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id),
  FOREIGN KEY (owner_character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_item_instances_owner ON item_instances(owner_character_id);
CREATE INDEX IF NOT EXISTS idx_item_instances_location ON item_instances(location_type, location_id);

CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS item_def_tags (
  item_def_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (item_def_id, tag_id),
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_item_def_tags_tag ON item_def_tags(tag_id);

ALTER TABLE equipment ADD COLUMN item_instance_id TEXT NULL;
CREATE INDEX IF NOT EXISTS idx_equipment_instance ON equipment(item_instance_id);


/* =========================================================
   2) Inventory QoL: containers + backpack upgrades
   ========================================================= */

CREATE TABLE IF NOT EXISTS containers (
  id TEXT PRIMARY KEY,
  owner_character_id TEXT NULL,
  name TEXT NOT NULL,
  capacity_weight REAL NOT NULL DEFAULT 99999.0,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (owner_character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS container_items (
  container_id TEXT NOT NULL,
  item_instance_id TEXT NOT NULL,
  PRIMARY KEY (container_id, item_instance_id),
  FOREIGN KEY (container_id) REFERENCES containers(id) ON DELETE CASCADE,
  FOREIGN KEY (item_instance_id) REFERENCES item_instances(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_container_items_container ON container_items(container_id);


/* =========================================================
   3) World data: settlements, POIs, factions, NPCs, buildings
   ========================================================= */

CREATE TABLE IF NOT EXISTS factions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  vibe TEXT NOT NULL DEFAULT '',
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS settlements_v2 (
  id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL, -- city/town/village
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  banner_color TEXT NOT NULL DEFAULT 'crimson',
  sigil_id TEXT NOT NULL DEFAULT 'sword',
  faction_id TEXT NULL,
  prosperity INTEGER NOT NULL DEFAULT 50,
  safety INTEGER NOT NULL DEFAULT 50,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (faction_id) REFERENCES factions(id)
);

CREATE INDEX IF NOT EXISTS idx_settlements_region ON settlements_v2(region_id);

CREATE TABLE IF NOT EXISTS pois (
  id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL, -- ruins/cave/camp/summit/dungeon/shrine
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  danger INTEGER NOT NULL DEFAULT 10,
  recommended_level INTEGER NOT NULL DEFAULT 1,
  icon TEXT NOT NULL DEFAULT '❓',
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_pois_region ON pois(region_id);

CREATE TABLE IF NOT EXISTS buildings (
  id TEXT PRIMARY KEY,
  settlement_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,           -- blacksmith/tavern/alchemist/general/temple/guildhall/stables/etc
  workstation TEXT NULL,        -- forge/alchemy/workbench/campfire
  faction_id TEXT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE,
  FOREIGN KEY (faction_id) REFERENCES factions(id)
);

CREATE INDEX IF NOT EXISTS idx_buildings_settlement ON buildings(settlement_id);

CREATE TABLE IF NOT EXISTS npcs (
  id TEXT PRIMARY KEY,
  settlement_id TEXT NOT NULL,
  building_id TEXT NULL,
  name TEXT NOT NULL,
  role TEXT NOT NULL,
  personality_tags TEXT NOT NULL DEFAULT '[]',
  dialogue_seed TEXT NOT NULL DEFAULT '',
  schedule_json TEXT NOT NULL DEFAULT '{}',
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE,
  FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_npcs_settlement ON npcs(settlement_id);
CREATE INDEX IF NOT EXISTS idx_npcs_building ON npcs(building_id);


/* =========================================================
   4) Shops + dynamic stock rules (alive economy foundation)
   ========================================================= */

CREATE TABLE IF NOT EXISTS shops (
  id TEXT PRIMARY KEY,
  settlement_id TEXT NOT NULL,
  building_id TEXT NULL,
  name TEXT NOT NULL,
  shop_type TEXT NOT NULL,       -- general/blacksmith/alchemist/tavern/stables
  buy_mult REAL NOT NULL DEFAULT 0.5,
  sell_mult REAL NOT NULL DEFAULT 1.0,
  restock_minutes INTEGER NOT NULL DEFAULT 60,
  last_restock_at INTEGER NOT NULL DEFAULT 0,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE,
  FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_shops_settlement ON shops(settlement_id);

CREATE TABLE IF NOT EXISTS shop_stock_rules (
  shop_id TEXT NOT NULL,
  item_def_id TEXT NOT NULL,
  min_qty INTEGER NOT NULL DEFAULT 0,
  max_qty INTEGER NOT NULL DEFAULT 5,
  weight INTEGER NOT NULL DEFAULT 10,
  price_mult REAL NOT NULL DEFAULT 1.0,
  PRIMARY KEY (shop_id, item_def_id),
  FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_shop_stock_rules_shop ON shop_stock_rules(shop_id);

CREATE TABLE IF NOT EXISTS shop_stock_tag_rules (
  shop_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  min_qty INTEGER NOT NULL DEFAULT 0,
  max_qty INTEGER NOT NULL DEFAULT 10,
  weight INTEGER NOT NULL DEFAULT 10,
  price_mult REAL NOT NULL DEFAULT 1.0,
  PRIMARY KEY (shop_id, tag_id),
  FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_shop_stock_tag_rules_shop ON shop_stock_tag_rules(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_stock_tag_rules_tag ON shop_stock_tag_rules(tag_id);


/* =========================================================
   5) Crafting system (all stations)
   ========================================================= */

CREATE TABLE IF NOT EXISTS recipes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  output_item_def_id TEXT NOT NULL,
  output_qty INTEGER NOT NULL DEFAULT 1,
  station TEXT NOT NULL, -- campfire/forge/alchemy/workbench
  difficulty INTEGER NOT NULL DEFAULT 1,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (output_item_def_id) REFERENCES item_defs(id)
);

CREATE TABLE IF NOT EXISTS recipe_ingredients (
  recipe_id TEXT NOT NULL,
  item_def_id TEXT NOT NULL,
  qty INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (recipe_id, item_def_id),
  FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id)
);

CREATE TABLE IF NOT EXISTS recipe_ingredient_tags (
  recipe_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  qty INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (recipe_id, tag_id),
  FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);


/* =========================================================
   6) Quests & objectives
   ========================================================= */

CREATE TABLE IF NOT EXISTS quest_defs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  giver_npc_id TEXT NULL,
  settlement_id TEXT NULL,
  min_level INTEGER NOT NULL DEFAULT 1,
  rewards_json TEXT NOT NULL DEFAULT '{}',
  steps_json TEXT NOT NULL DEFAULT '[]',
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (giver_npc_id) REFERENCES npcs(id) ON DELETE SET NULL,
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS character_quests (
  character_id TEXT NOT NULL,
  quest_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  progress_json TEXT NOT NULL DEFAULT '{}',
  started_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (character_id, quest_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (quest_id) REFERENCES quest_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_character_quests_char ON character_quests(character_id);

CREATE TABLE IF NOT EXISTS character_objectives (
  id TEXT PRIMARY KEY,
  character_id TEXT NOT NULL,
  text TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'active',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_character_objectives_char ON character_objectives(character_id);


/* =========================================================
   7) AI-friendly world events log
   ========================================================= */

CREATE TABLE IF NOT EXISTS world_events (
  id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  settlement_id TEXT NULL,
  poi_id TEXT NULL,
  character_id TEXT NULL,
  type TEXT NOT NULL,
  text TEXT NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_world_events_region ON world_events(region_id);
CREATE INDEX IF NOT EXISTS idx_world_events_character ON world_events(character_id);


/* =========================================================
   7.5) AI inventory hints
   ========================================================= */

CREATE TABLE IF NOT EXISTS ai_item_hints (
  item_def_id TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 50,
  hint_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);


/* =========================================================
   9) NEXT PACK: Reputation + Skills + Loot + Repair Logs
   ========================================================= */

-- Faction reputation per character (drives dialogue, pricing, access)
CREATE TABLE IF NOT EXISTS character_faction_rep (
  character_id TEXT NOT NULL,
  faction_id TEXT NOT NULL,
  rep INTEGER NOT NULL DEFAULT 0,          -- -100..+100-ish
  last_updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (character_id, faction_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (faction_id) REFERENCES factions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_char_faction_rep_char ON character_faction_rep(character_id);

-- Simple skills (crafting, survival, diplomacy, etc.)
CREATE TABLE IF NOT EXISTS skills (
  id TEXT PRIMARY KEY,            -- skill_crafting
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS character_skills (
  character_id TEXT NOT NULL,
  skill_id TEXT NOT NULL,
  level INTEGER NOT NULL DEFAULT 1,
  xp INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (character_id, skill_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (skill_id) REFERENCES skills(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_character_skills_char ON character_skills(character_id);

-- Crafting outcomes log (helps AI narrate + helps debugging)
CREATE TABLE IF NOT EXISTS crafting_log (
  id TEXT PRIMARY KEY,                 -- log_xxx
  character_id TEXT NOT NULL,
  recipe_id TEXT NOT NULL,
  success INTEGER NOT NULL DEFAULT 1,  -- 1/0
  notes TEXT NOT NULL DEFAULT '',
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_crafting_log_char ON crafting_log(character_id);

-- Repair log (durability narration + analytics)
CREATE TABLE IF NOT EXISTS repair_log (
  id TEXT PRIMARY KEY,                 -- rlog_xxx
  character_id TEXT NOT NULL,
  item_instance_id TEXT NOT NULL,
  repair_item_def_id TEXT NOT NULL,    -- e.g. metal kit
  durability_before INTEGER NOT NULL,
  durability_after INTEGER NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (item_instance_id) REFERENCES item_instances(id) ON DELETE CASCADE,
  FOREIGN KEY (repair_item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_repair_log_char ON repair_log(character_id);

-- Loot tables: “this chest draws from these entries”
CREATE TABLE IF NOT EXISTS loot_tables (
  id TEXT PRIMARY KEY,               -- lt_ruins_low
  name TEXT NOT NULL,
  roll_count INTEGER NOT NULL DEFAULT 1, -- how many draws
  meta_json TEXT NOT NULL DEFAULT '{}'
);

-- Direct item entries
CREATE TABLE IF NOT EXISTS loot_table_entries (
  loot_table_id TEXT NOT NULL,
  item_def_id TEXT NOT NULL,
  min_qty INTEGER NOT NULL DEFAULT 1,
  max_qty INTEGER NOT NULL DEFAULT 1,
  weight INTEGER NOT NULL DEFAULT 10,
  PRIMARY KEY (loot_table_id, item_def_id),
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);

-- Tag-based loot entries (pull “any herb”, “any ammo”, etc.)
CREATE TABLE IF NOT EXISTS loot_table_tag_entries (
  loot_table_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  min_qty INTEGER NOT NULL DEFAULT 1,
  max_qty INTEGER NOT NULL DEFAULT 1,
  weight INTEGER NOT NULL DEFAULT 10,
  PRIMARY KEY (loot_table_id, tag_id),
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_loot_entries_table ON loot_table_entries(loot_table_id);
CREATE INDEX IF NOT EXISTS idx_loot_tag_entries_table ON loot_table_tag_entries(loot_table_id);

-- Attach loot tables to POIs and Buildings
CREATE TABLE IF NOT EXISTS poi_loot (
  poi_id TEXT NOT NULL,
  loot_table_id TEXT NOT NULL,
  respawn_minutes INTEGER NOT NULL DEFAULT 120,
  last_looted_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (poi_id, loot_table_id),
  FOREIGN KEY (poi_id) REFERENCES pois(id) ON DELETE CASCADE,
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS building_loot (
  building_id TEXT NOT NULL,
  loot_table_id TEXT NOT NULL,
  respawn_minutes INTEGER NOT NULL DEFAULT 120,
  last_looted_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (building_id, loot_table_id),
  FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE
);


/* =========================================================
   8) Seed data: factions, towns, POIs, tags, items, recipes, shops, NPCs
   ========================================================= */

INSERT OR IGNORE INTO factions (id, name, vibe) VALUES
('faction_merchants_guild', 'Merchants Guild', 'Coin talks, but contracts talk louder.'),
('faction_wardens', 'Hearth Wardens', 'Protectors of roads, villages, and the innocent.'),
('faction_iron_oath', 'Iron Oath', 'Stubborn crafters with proud traditions.'),
('faction_wayfarer_concord', 'Wayfarer Concord', 'No road stands alone.'),
('faction_ashen_circle', 'Ashen Circle', 'From ruin, truth.'),
('faction_verdant_oath', 'Verdant Oath', 'The land remembers.'),
('faction_blackwake_brotherhood', 'Blackwake Brotherhood', 'What sinks belongs to us.');

INSERT OR IGNORE INTO settlements_v2 (id, region_id, name, type, x, y, faction_id, prosperity, safety, banner_color, sigil_id) VALUES
('set_cinderport',   'hearthlands', 'Cinderport',   'city',    48, 14, 'faction_merchants_guild', 70, 55, 'royal_blue', 'crown'),
('set_brindlewick',  'hearthlands', 'Brindlewick',  'village', 20, 18, 'faction_wardens',         45, 65, 'emerald',  'shield'),
('set_frostford',    'hearthlands', 'Frostford',    'village', 18, 48, 'faction_wardens',         40, 55, 'ice',      'star'),
('set_oakrest',      'hearthlands', 'Oakrest',      'village', 62, 20, 'faction_iron_oath',        50, 60, 'copper',   'oak'),
('set_stonebrook',   'hearthlands', 'Stonebrook',   'village', 60, 46, 'faction_iron_oath',        55, 58, 'crimson',  'hammer'),
('set_emberhold',    'hearthlands', 'Emberhold',    'town',    40, 28, 'faction_iron_oath',        60, 55, 'scarlet',  'hammer'),
('set_stoneford',    'hearthlands', 'Stoneford',    'town',    30, 32, 'faction_wardens',          55, 62, 'midnight', 'shield'),
('set_pinehollow',   'hearthlands', 'Pinehollow',   'town',    12, 24, 'faction_wardens',          48, 50, 'emerald',  'wolf'),
('set_mistvale',     'hearthlands', 'Mistvale',     'village', 68, 34, 'faction_merchants_guild',  46, 48, 'teal',     'moon');

INSERT OR IGNORE INTO pois (id, region_id, name, type, x, y, danger, recommended_level, icon, meta_json) VALUES
('poi_blackbarrow_ruins', 'hearthlands', 'Blackbarrow Ruins', 'ruins', 26, 14, 25, 2, '🏚️', '{"lootTier":"low","theme":"undead"}'),
('poi_mossjaw_cave',      'hearthlands', 'Mossjaw Cave',      'cave',  10, 30, 35, 3, '🕳️', '{"lootTier":"mid","theme":"beasts"}'),
('poi_roadside_bandits',  'hearthlands', 'Roadside Bandit Camp','camp', 36, 22, 30, 2, '⛺', '{"faction":"bandits","bounty":120}'),
('poi_sablecliff_camp',   'hearthlands', 'Sablecliff Camp',   'camp',  58, 28, 45, 4, '⛺', '{"faction":"bandits","bounty":180}'),
('poi_ashen_summit',      'hearthlands', 'Ashen Summit',      'summit',44,  6, 85, 8, '⛰️', '{"special":"dragon_taming"}');

INSERT OR IGNORE INTO tags (id, label) VALUES
('material:wood', 'Wood'),
('material:iron', 'Iron'),
('material:leather', 'Leather'),
('material:cloth', 'Cloth'),
('material:stone', 'Stone'),

('station:campfire', 'Campfire'),
('station:forge', 'Forge'),
('station:alchemy', 'Alchemy'),
('station:workbench', 'Workbench'),

('item:food', 'Food'),
('item:weapon', 'Weapon'),
('item:armor', 'Armor'),
('item:resource', 'Resource'),
('item:tool', 'Tool'),
('item:trinket', 'Trinket'),
('item:ammo', 'Ammo'),
('item:component', 'Component'),

('ingredient:herb', 'Herb'),
('ingredient:meat', 'Meat'),

('use:heal', 'Healing'),
('use:stamina', 'Stamina'),
('use:light', 'Light'),
('use:repair', 'Repair'),

('ammo:arrow', 'Arrow Ammo'),
('ammo:bolt', 'Bolt Ammo'),
('ammo:pebble', 'Pebble Ammo'),

('repair:iron', 'Repairs Iron Gear'),
('repair:leather', 'Repairs Leather Gear'),

('rarity:common', 'Common'),
('rarity:uncommon', 'Uncommon'),
('rarity:rare', 'Rare'),
('rarity:epic', 'Epic'),
('rarity:legendary', 'Legendary');

-- NEW: skills seed
INSERT OR IGNORE INTO skills (id, name, description, meta_json) VALUES
('skill_crafting', 'Crafting', 'Make gear, tools, and supplies more efficiently.', '{"affects":["forge","workbench","alchemy","campfire"]}'),
('skill_survival', 'Survival', 'Travel, camp, hunt, and avoid danger.', '{"affects":["encounters","food","camping"]}'),
('skill_diplomacy', 'Diplomacy', 'Better deals and better outcomes with factions.', '{"affects":["prices","rep_gains"]}'),
('skill_combat', 'Combat', 'Stronger attacks and smarter fighting.', '{"affects":["damage","stamina"]}');



/* =========================================================
   ITEM DEFINITIONS (expanded)
   ========================================================= */

INSERT OR IGNORE INTO item_defs
(id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json) VALUES

-- =========================================================
-- RESOURCES / COMPONENTS (flavor + craft hooks)
-- =========================================================
('itm_wood',        'Wood (Bundle)',         'resource', NULL, 'common', 1, 50, 1, 0.5, 0, '{"tags":["item:resource","material:wood"],"flavor":"Sturdy kindling and planks."}'),
('itm_stone',       'Stone (Chunk)',         'resource', NULL, 'common', 1, 50, 1, 0.7, 0, '{"tags":["item:resource","material:stone"],"flavor":"Rough stone for building or throwing."}'),
('itm_iron_ore',    'Iron Ore',              'resource', NULL, 'common', 1, 50, 3, 0.8, 0, '{"tags":["item:resource","material:iron"],"flavor":"Speckled ore that wants to become a blade."}'),
('itm_leather',     'Leather (Hide)',        'resource', NULL, 'common', 1, 50, 2, 0.4, 0, '{"tags":["item:resource","material:leather"],"flavor":"Tanned hide—good for straps and armor."}'),
('itm_cloth',       'Cloth (Bolt)',          'resource', NULL, 'common', 1, 50, 2, 0.3, 0, '{"tags":["item:resource","material:cloth"],"flavor":"A bolt of cloth—useful for wraps and tunics."}'),
('itm_meat',        'Meat (Fresh Cut)',      'resource', NULL, 'common', 1, 20, 3, 0.4, 0, '{"tags":["item:resource","ingredient:meat"],"flavor":"Fresh cut meat—best cooked soon."}'),

('itm_iron_ingot',     'Iron Ingot',         'component', NULL, 'common', 1, 50, 6, 0.7, 0, '{"tags":["item:component","material:iron","use:repair","use:craft"],"flavor":"A clean bar of iron—smiths love these."}'),
('itm_leather_strap',  'Leather Strap',      'component', NULL, 'common', 1, 50, 4, 0.2, 0, '{"tags":["item:component","material:leather","use:repair"],"flavor":"A sturdy strap with a simple buckle."}'),
('itm_wax',            'Beeswax',            'component', NULL, 'common', 1, 50, 2, 0.1, 0, '{"tags":["item:component","use:repair","use:craft"],"flavor":"Wax for sealing, polishing, and quiet fixes."}'),
('itm_pitch',          'Pine Pitch',         'component', NULL, 'common', 1, 30, 2, 0.2, 0, '{"tags":["item:component","use:repair"],"flavor":"Sticky pitch—great for patching cracks."}'),
('itm_thread',         'Strong Thread',      'component', NULL, 'common', 1, 50, 1, 0.1, 0, '{"tags":["item:component","use:repair","material:cloth"],"flavor":"Waxed thread that bites into cloth and leather."}'),
('itm_rivets',         'Iron Rivets (Set)',  'component', NULL, 'common', 1, 50, 2, 0.2, 0, '{"tags":["item:component","use:repair","material:iron"],"flavor":"Tiny metal teeth for armor fixes."}'),
('itm_resin',          'Amber Resin',        'component', NULL, 'uncommon',1, 30, 7, 0.1, 0, '{"tags":["item:component","use:craft"],"flavor":"A golden resin used in fine varnish and charms."}'),

-- =========================================================
-- FOOD / CONSUMABLES (D&D-ish)
-- =========================================================
('itm_bread',       'Bread Loaf',            'consumable', NULL, 'common', 1, 10, 1, 0.2, 0, '{"heal":2,"tags":["item:food","use:heal"],"flavor":"Warm enough to make you brave."}'),
('itm_jerky',       'Jerky Strip',           'consumable', NULL, 'common', 1, 10, 2, 0.2, 0, '{"stamina":2,"tags":["item:food","use:stamina"],"flavor":"Dry, salty, and reliable."}'),
('itm_rations',     'Travel Rations',        'consumable', NULL, 'common', 1, 10, 5, 0.6, 0, '{"stamina":4,"tags":["item:food","use:stamina"],"flavor":"Hardtack, nuts, and dried fruit—adventurer fuel."}'),
('itm_cheese',      'Cheese Wheel',          'consumable', NULL, 'common', 1, 5,  4, 0.7, 0, '{"heal":3,"tags":["item:food","use:heal"],"flavor":"Smells strong. Tastes stronger."}'),
('itm_honey',       'Jar of Honey',          'consumable', NULL, 'uncommon',1, 5,  8, 0.8, 0, '{"heal":4,"tags":["item:food","use:heal"],"flavor":"Sweet gold—good for morale and sore throats."}'),
('itm_water_flask', 'Waterskin',             'consumable', NULL, 'common', 1, 3,  2, 0.9, 0, '{"stamina":2,"tags":["item:food","use:stamina"],"flavor":"Cool water on a dusty road."}'),

('itm_bandage',     'Bandage Roll',          'consumable', NULL, 'common', 1, 10, 5, 0.2, 0, '{"heal":5,"tags":["use:heal","item:medical"],"flavor":"Clean cloth strips—wrap it tight."}'),
('itm_splint',      'Splint Kit',            'consumable', NULL, 'uncommon',1, 5,  12,0.6, 0, '{"heal":8,"tags":["use:heal","item:medical"],"flavor":"Wood, cloth, and know-how in a pouch."}'),

-- =========================================================
-- POTIONS / DRAUGHTS (tiered)
-- =========================================================
('itm_small_potion',    'Potion of Healing (Small)',  'consumable', NULL, 'uncommon', 1, 5,  18, 0.5, 0, '{"heal":10,"tags":["use:heal","item:potion"],"flavor":"A red swirl that tastes like cinnamon."}'),
('itm_medium_potion',   'Potion of Healing (Medium)', 'consumable', NULL, 'rare',     1, 3,  45, 0.6, 0, '{"heal":25,"tags":["use:heal","item:potion"],"flavor":"A deeper red—warmth spreads fast."}'),
('itm_stamina_draught', 'Stamina Draught',            'consumable', NULL, 'uncommon', 1, 5,  20, 0.5, 0, '{"stamina":12,"tags":["use:stamina","item:potion"],"flavor":"Tastes like mint and thunder."}'),
('itm_focus_tonic',     'Focus Tonic',                'consumable', NULL, 'rare',     1, 3,  40, 0.4, 0, '{"focus":1,"tags":["use:focus","item:potion"],"flavor":"Sharpens your thoughts like a whetstone."}'),

-- =========================================================
-- TOOLS
-- =========================================================
('itm_torch',         'Torch',               'tool', NULL, 'common',   1,  5,  1, 0.6, 0, '{"light":1,"tags":["item:tool","use:light"],"flavor":"A simple flame that makes shadows behave."}'),
('itm_flint_steel',   'Flint & Steel',       'tool', NULL, 'common',   1,  1,  5, 0.2, 0, '{"tags":["item:tool","use:fire"],"flavor":"Sparks on demand."}'),
('itm_rope',          'Rope (50 ft)',        'tool', NULL, 'common',   1,  1,  10,1.0, 0, '{"tags":["item:tool","use:climb"],"flavor":"Hemp rope with a trustworthy bite."}'),
('itm_lockpicks',     'Lockpicks (Simple)',  'tool', NULL, 'uncommon', 1,  1,  25,0.1, 0, '{"tags":["item:tool","use:lockpick"],"flavor":"For doors that think they’re clever."}'),

-- =========================================================
-- REPAIR KITS (material-targeted)
-- =========================================================
('itm_repair_kit_iron',    'Metal Repair Kit',    'tool', NULL, 'uncommon', 1, 10, 22, 0.8, 0, '{"repair":{"amount":30,"targets":["material:iron"],"uses":3},"tags":["item:tool","use:repair","repair:iron"],"flavor":"Rivets, oil, and a tiny hammer."}'),
('itm_repair_kit_leather', 'Leather Repair Kit',  'tool', NULL, 'uncommon', 1, 10, 18, 0.6, 0, '{"repair":{"amount":30,"targets":["material:leather"],"uses":3},"tags":["item:tool","use:repair","repair:leather"],"flavor":"Needle, waxed thread, and patches."}'),
('itm_repair_kit_cloth',   'Cloth Repair Kit',    'tool', NULL, 'common',   1, 10, 12, 0.4, 0, '{"repair":{"amount":20,"targets":["material:cloth"],"uses":3},"tags":["item:tool","use:repair","repair:cloth"],"flavor":"Thread and a little patience."}'),

-- =========================================================
-- AMMO
-- =========================================================
('itm_arrow',   'Arrow',   'ammo', NULL, 'common', 1, 50, 1, 0.1, 0, '{"tags":["item:ammo","ammo:arrow"],"flavor":"Straight shaft, sharp promise."}'),
('itm_bolt',    'Bolt',    'ammo', NULL, 'common', 1, 50, 1, 0.1, 0, '{"tags":["item:ammo","ammo:bolt"],"flavor":"Short and mean."}'),
('itm_pebble',  'Pebble',  'ammo', NULL, 'common', 1, 99, 1, 0.1, 0, '{"tags":["item:ammo","ammo:pebble"],"flavor":"Nature’s cheapest projectile."}'),

-- =========================================================
-- WEAPONS (starter + a few extra flavor picks)
-- =========================================================
('itm_wooden_club',    'Wooden Club',    'weapon','mainhand','common',   0, 1,  4, 2.5, 40, '{"damage":2,"tags":["item:weapon","material:wood"],"flavor":"Simple, honest bonking."}'),
('itm_training_sword', 'Training Sword', 'weapon','mainhand','common',   0, 1,  6, 2.0, 45, '{"damage":2,"tags":["item:weapon"],"flavor":"Blunt edge—perfect for practice duels."}'),
('itm_iron_dagger',    'Iron Dagger',    'weapon','offhand','common',    0, 1, 14, 1.0, 65, '{"damage":3,"tags":["item:weapon","material:iron"],"flavor":"A quiet blade for quick problems."}'),
('itm_iron_sword',     'Iron Sword',     'weapon','mainhand','common',   0, 1, 25, 3.5, 80, '{"damage":5,"tags":["item:weapon","material:iron"],"flavor":"A classic adventurer’s companion."}'),
('itm_spear',          'Spear',          'weapon','mainhand','common',   0, 1, 20, 3.0, 75, '{"damage":4,"reach":1,"tags":["item:weapon","material:wood"],"flavor":"Keeps teeth away from you."}'),
('itm_short_bow',      'Short Bow',      'weapon','mainhand','uncommon', 0, 1, 20, 2.0, 70, '{"damage":4,"ranged":1,"ammo":"ammo:arrow","tags":["item:weapon","material:wood"],"flavor":"Light, fast, and forgiving."}'),
('itm_crossbow',       'Crossbow',       'weapon','mainhand','uncommon', 0, 1, 35, 4.0, 90, '{"damage":6,"ranged":1,"ammo":"ammo:bolt","tags":["item:weapon","material:wood","material:iron"],"flavor":"Point, click, thunk."}'),
('itm_greatsword', 'Greatsword', 'weapon', 'mainhand', 'uncommon', 0, 1, 50, 6.0, 100, '{"damage":8, "two_handed":true, "tags":["item:weapon","material:iron","heavy"], "flavor":"A massive blade requiring two hands and a stout heart."}'),
('itm_warhammer', 'Warhammer', 'weapon', 'mainhand', 'uncommon', 0, 1, 15, 2.0, 90, '{"damage":6, "versatile":true, "tags":["item:weapon","material:iron"], "flavor":"The preferred tool for crushing plate armor and skeletons alike."}'),
('itm_rapier', 'Rapier', 'weapon', 'mainhand', 'uncommon', 0, 1, 25, 2.0, 75, '{"damage":5, "finesse":true, "tags":["item:weapon","material:iron"], "flavor":"A needle-thin blade for the precise and the patient."}'),
('itm_greataxe', 'Greataxe', 'weapon', 'mainhand', 'uncommon', 0, 1, 30, 7.0, 95, '{"damage":9, "two_handed":true, "tags":["item:weapon","material:iron","heavy"], "flavor":"A wicked, double-bitted axe built for total cleaving."}'),
('itm_maul', 'Maul', 'weapon', 'mainhand', 'uncommon', 0, 1, 10, 10.0, 110, '{"damage":8, "heavy":true, "tags":["item:weapon","material:iron","material:wood"], "flavor":"Essentially a boulder on a stick. Effective."}'),
('itm_longbow', 'Longbow', 'weapon', 'mainhand', 'uncommon', 0, 1, 50, 2.0, 80, '{"damage":6, "ranged":true, "heavy":true, "ammo":"ammo:arrow", "tags":["item:weapon","material:wood"], "flavor":"A bow nearly as tall as its wielder."}'),
('itm_scimitar', 'Scimitar', 'weapon', 'mainhand', 'common', 0, 1, 25, 3.0, 70, '{"damage":4, "finesse":true, "tags":["item:weapon","material:iron"], "flavor":"A curved blade that flows like water in a desert wind."}'),

-- =========================================================
-- ARMOR (starter)
-- =========================================================
('itm_cloth_cap',    'Cloth Cap',      'armor','helmet','common', 0,1, 4, 0.4,30,'{"armor":1,"tags":["item:armor","material:cloth"],"flavor":"Keeps sun off and pride intact."}'),
('itm_cloth_tunic',  'Cloth Tunic',    'armor','torso','common',  0,1, 8, 1.5,50,'{"armor":1,"tags":["item:armor","material:cloth"],"flavor":"Better than fighting in pajamas."}'),
('itm_leather_cap',  'Leather Cap',    'armor','helmet','common', 0,1,12, 1.2,60,'{"armor":1,"tags":["item:armor","material:leather"],"flavor":"Smells like adventure and old rain."}'),
('itm_leather_vest', 'Leather Vest',   'armor','torso','common',  0,1,22, 4.0,90,'{"armor":2,"tags":["item:armor","material:leather"],"flavor":"Tough enough for brambles and bruises."}'),
('itm_padded_armor', 'Padded Armor', 'armor', 'torso', 'common', 0, 1, 5, 8.0, 40, '{"armor":1, "disadvantage_stealth":true, "tags":["item:armor","material:cloth"], "flavor":"Thick, quilted layers. Hot, itchy, but better than nothing."}'),
('itm_hide_armor', 'Hide Armor', 'armor', 'torso', 'common', 0, 1, 10, 12.0, 60, '{"armor":2, "tags":["item:armor","material:leather"], "flavor":"Rough-hewn furs and thick pelts from a successful hunt."}'),
('itm_scale_mail', 'Scale Mail', 'armor', 'torso', 'uncommon', 0, 1, 50, 45.0, 120, '{"armor":4, "disadvantage_stealth":true, "tags":["item:armor","material:iron"], "flavor":"Overlapping metal scales that clatter like a thousand coins."}'),
('itm_breastplate', 'Breastplate', 'armor', 'torso', 'rare', 0, 1, 400, 20.0, 150, '{"armor":4, "tags":["item:armor","material:iron"], "flavor":"Polished steel protecting the vitals without sacrificing mobility."}'),

-- =========================================================
-- HEAVY ARMOR & SHIELDS
-- =========================================================
('itm_chain_mail', 'Chain Mail', 'armor', 'torso', 'uncommon', 0, 1, 75, 55.0, 180, '{"armor":6, "disadvantage_stealth":true, "min_strength":13, "tags":["item:armor","material:iron"], "flavor":"A mesh of interlocking rings. Classic knightly protection."}'),
('itm_plate_armor', 'Full Plate', 'armor', 'torso', 'epic', 0, 1, 1500, 65.0, 300, '{"armor":8, "disadvantage_stealth":true, "min_strength":15, "tags":["item:armor","material:iron"], "flavor":"A masterpiece of the forge. You are a walking fortress."}'),
('itm_shield_wooden', 'Wooden Shield', 'armor', 'offhand', 'common', 0, 1, 10, 6.0, 80, '{"armor":2, "tags":["item:armor","material:wood"], "flavor":"A sturdy oak disc bound with iron."}'),
('itm_shield_steel', 'Steel Shield', 'armor', 'offhand', 'uncommon', 0, 1, 20, 10.0, 150, '{"armor":2, "tags":["item:armor","material:iron"], "flavor":"A polished heater shield bearing the scars of many battles."}'),

-- =========================================================
-- SPECIAL/MAGICAL TIER (D&D Flavor)
-- =========================================================
('itm_sunblade', 'Sunblade', 'weapon', 'mainhand', 'epic', 0, 1, 5000, 0.0, 0, '{"damage":10, "finesse":true, "light":true, "damage_type":"radiant", "tags":["item:weapon","magical"], "flavor":"A hilt that projects a blade of pure, burning sunlight."}'),
('itm_mithral_shirt', 'Mithral Chain Shirt', 'armor', 'torso', 'rare', 0, 1, 800, 10.0, 200, '{"armor":3, "tags":["item:armor","material:mithral"], "flavor":"Gleams like silver but is light as silk. Can be worn under clothes."}'),
('itm_adamantine_plate', 'Adamantine Plate', 'armor', 'torso', 'legendary', 0, 1, 5000, 65.0, 1000, '{"armor":8, "crit_immune":true, "tags":["item:armor","material:adamantine"], "flavor":"Forged from the heart of a fallen star. Nothing breaks this."}'),

-- =========================================================
-- TRINKETS (kid-safe magic vibes)
-- =========================================================
('itm_lucky_coin',   'Lucky Coin',      'trinket',NULL,'uncommon',0,1,15,0.1,0,'{"luck":1,"tags":["item:trinket"],"flavor":"Warm in your palm when you need it."}'),
('itm_glow_pebble',  'Glow Pebble',     'trinket',NULL,'common',  0,1, 8,0.2,0,'{"light":1,"tags":["item:trinket","use:light"],"flavor":"A pebble that refuses to be ordinary."}'),
('itm_brave_badge',  'Brave Badge',     'trinket',NULL,'uncommon',0,1,20,0.2,0,'{"brave":1,"tags":["item:trinket"],"flavor":"Feels heavier when you’re scared—like it’s reminding you."}'),
('itm_whisper_charm','Whisper Charm',   'trinket',NULL,'rare',    0,1,55,0.1,0,'{"stealth":1,"tags":["item:trinket"],"flavor":"Makes your footsteps sound like distant snow."}'),
('itm_spark_ring',   'Spark Ring',      'trinket',NULL,'rare',    0,1,60,0.1,0,'{"spark":1,"tags":["item:trinket"],"flavor":"A tiny crackle follows your grin."}'),

-- =========================================================
-- HERBS (alchemy ingredients)
-- =========================================================
('itm_healing_herb', 'Healing Herb',    'resource',NULL,'common',  1,20, 4,0.1,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"],"flavor":"Smells clean—like a sunny morning."}'),
('itm_mint_leaf',    'Mint Leaf',       'resource',NULL,'common',  1,30, 2,0.05,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"],"flavor":"Fresh enough to wake a sleepy wizard."}'),
('itm_sunpetal',     'Sunpetal',        'resource',NULL,'uncommon',1,20, 6,0.05,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"],"flavor":"Golden petals that hold warmth."}'),
('itm_nightshade',   'Nightshade (Tame)', 'resource',NULL,'rare',  1,10, 18,0.05,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"],"flavor":"Handled carefully; used in tiny, safe doses."}'),
('itm_dreamroot',    'Dreamroot',       'resource',NULL,'rare',    1,10, 22,0.08,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"],"flavor":"Smells like rain and forgotten songs."}');



/* =========================================================
   Tag links (query-friendly)
   ========================================================= */

-- Materials
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_wood', 'material:wood'),
('itm_stone', 'material:stone'),
('itm_iron_ore', 'material:iron'),
('itm_leather', 'material:leather'),
('itm_cloth', 'material:cloth'),
('itm_iron_ingot', 'material:iron'),
('itm_leather_strap', 'material:leather'),
('itm_thread', 'material:cloth'),
('itm_rivets', 'material:iron'),
('itm_shield_wooden', 'material:wood'),
('itm_shield_steel', 'material:iron'),
('itm_mithral_shirt', 'material:mithral'),
('itm_adamantine_plate', 'material:adamantine');

-- Weapons (D&D grouped)
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_wooden_club', 'item:weapon'),
('itm_training_sword', 'item:weapon'),
('itm_iron_dagger', 'item:weapon'),
('itm_iron_sword', 'item:weapon'),
('itm_spear', 'item:weapon'),
('itm_short_bow', 'item:weapon'),
('itm_crossbow', 'item:weapon'),
('itm_greatsword', 'item:weapon'),
('itm_warhammer', 'item:weapon'),
('itm_rapier', 'item:weapon'),
('itm_greataxe', 'item:weapon'),
('itm_maul', 'item:weapon'),
('itm_longbow', 'item:weapon'),
('itm_scimitar', 'item:weapon'),
('itm_sunblade', 'item:weapon');

-- Armor
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_cloth_cap', 'item:armor'),
('itm_cloth_tunic', 'item:armor'),
('itm_leather_cap', 'item:armor'),
('itm_leather_vest', 'item:armor'),
('itm_padded_armor', 'item:armor'),
('itm_hide_armor', 'item:armor'),
('itm_scale_mail', 'item:armor'),
('itm_breastplate', 'item:armor'),
('itm_chain_mail', 'item:armor'),
('itm_plate_armor', 'item:armor'),
('itm_shield_wooden', 'item:armor'),
('itm_shield_steel', 'item:armor'),
('itm_mithral_shirt', 'item:armor'),
('itm_adamantine_plate', 'item:armor');

-- Food & Recovery
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_bread', 'item:food'),
('itm_jerky', 'item:food'),
('itm_rations', 'item:food'),
('itm_cheese', 'item:food'),
('itm_honey', 'item:food'),
('itm_water_flask', 'item:food'),
('itm_bread', 'use:heal'),
('itm_cheese', 'use:heal'),
('itm_honey', 'use:heal'),
('itm_jerky', 'use:stamina'),
('itm_rations', 'use:stamina'),
('itm_water_flask', 'use:stamina');

-- Medical & Potions
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_bandage', 'item:medical'),
('itm_splint', 'item:medical'),
('itm_bandage', 'use:heal'),
('itm_splint', 'use:heal'),
('itm_small_potion', 'item:potion'),
('itm_medium_potion', 'item:potion'),
('itm_stamina_draught', 'item:potion'),
('itm_focus_tonic', 'item:potion'),
('itm_small_potion', 'use:heal'),
('itm_medium_potion', 'use:heal'),
('itm_stamina_draught', 'use:stamina'),
('itm_focus_tonic', 'use:focus');

-- Tools & Utility
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_torch', 'item:tool'),
('itm_flint_steel', 'item:tool'),
('itm_rope', 'item:tool'),
('itm_lockpicks', 'item:tool'),
('itm_torch', 'use:light'),
('itm_flint_steel', 'use:fire'),
('itm_rope', 'use:climb'),
('itm_lockpicks', 'use:lockpick');

-- Repair Kits & Components
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_repair_kit_iron', 'item:tool'),
('itm_repair_kit_leather', 'item:tool'),
('itm_repair_kit_cloth', 'item:tool'),
('itm_repair_kit_iron', 'use:repair'),
('itm_repair_kit_leather', 'use:repair'),
('itm_repair_kit_cloth', 'use:repair'),
('itm_iron_ingot', 'use:repair'),
('itm_leather_strap', 'use:repair'),
('itm_thread', 'use:repair'),
('itm_rivets', 'use:repair'),
('itm_wax', 'use:repair'),
('itm_pitch', 'use:repair');

-- Ammo
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_arrow', 'item:ammo'),
('itm_bolt', 'item:ammo'),
('itm_pebble', 'item:ammo'),
('itm_arrow', 'ammo:arrow'),
('itm_bolt', 'ammo:bolt'),
('itm_pebble', 'ammo:pebble');

-- Alchemy & Ingredients
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_healing_herb', 'ingredient:herb'),
('itm_mint_leaf', 'ingredient:herb'),
('itm_sunpetal', 'ingredient:herb'),
('itm_nightshade', 'ingredient:herb'),
('itm_dreamroot', 'ingredient:herb'),
('itm_meat', 'ingredient:meat'),
('itm_healing_herb', 'station:alchemy'),
('itm_mint_leaf', 'station:alchemy'),
('itm_sunpetal', 'station:alchemy'),
('itm_nightshade', 'station:alchemy'),
('itm_dreamroot', 'station:alchemy');

-- Trinkets
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_lucky_coin', 'item:trinket'),
('itm_glow_pebble', 'item:trinket'),
('itm_brave_badge', 'item:trinket'),
('itm_whisper_charm', 'item:trinket'),
('itm_spark_ring', 'item:trinket'),
('itm_glow_pebble', 'use:light');



/* =========================================================
   Recipes (expanded)
   ========================================================= */

INSERT OR IGNORE INTO recipes (id, name, output_item_def_id, output_qty, station, difficulty, meta_json) VALUES
-- =========================================================
-- CAMPFIRE (Survival & Basic Food)
-- =========================================================
('rcp_campfire_rations',   'Pack Travel Rations', 'itm_rations',     1, 'campfire',  1, '{"timeSec":30}'),
('rcp_campfire_honey',    'Process Wild Honey',  'itm_honey',       1, 'campfire',  2, '{"timeSec":40}'),

-- =========================================================
-- ALCHEMY STATION (Advanced Draughts)
-- =========================================================
('rcp_focus_tonic',        'Distill Focus Tonic', 'itm_focus_tonic', 1, 'alchemy',   4, '{"timeSec":50}'),

-- =========================================================
-- FORGE (D&D Martial Gear)
-- =========================================================
('rcp_forge_greatsword',   'Forge Greatsword',    'itm_greatsword',  1, 'forge',     5, '{"timeSec":75}'),
('rcp_forge_warhammer',    'Forge Warhammer',     'itm_warhammer',   1, 'forge',     3, '{"timeSec":45}'),
('rcp_forge_rapier',       'Forge Rapier',        'itm_rapier',      1, 'forge',     4, '{"timeSec":55}'),
('rcp_forge_greataxe',     'Forge Greataxe',      'itm_greataxe',    1, 'forge',     5, '{"timeSec":80}'),
('rcp_forge_maul',         'Forge Maul',          'itm_maul',        1, 'forge',     4, '{"timeSec":70}'),
('rcp_forge_scimitar',     'Forge Scimitar',      'itm_scimitar',    1, 'forge',     3, '{"timeSec":50}'),
('rcp_forge_steel_shield', 'Forge Steel Shield',  'itm_shield_steel',1, 'forge',     3, '{"timeSec":45}'),

('rcp_forge_scale_mail',   'Forge Scale Mail',    'itm_scale_mail',  1, 'forge',     4, '{"timeSec":90}'),
('rcp_forge_breastplate',  'Forge Breastplate',   'itm_breastplate', 1, 'forge',     5, '{"timeSec":110}'),
('rcp_forge_chain_mail',   'Forge Chain Mail',    'itm_chain_mail',  1, 'forge',     4, '{"timeSec":120}'),
('rcp_forge_plate_armor',  'Forge Full Plate',    'itm_plate_armor', 1, 'forge',     6, '{"timeSec":240}'),

-- =========================================================
-- WORKBENCH (Leather, Cloth, & Woodworking)
-- =========================================================
('rcp_padded_armor',       'Quilt Padded Armor',  'itm_padded_armor','1','workbench', 2, '{"timeSec":60}'),
('rcp_hide_armor',         'Cure Hide Armor',     'itm_hide_armor',  1, 'workbench', 3, '{"timeSec":70}'),
('rcp_wooden_shield',      'Craft Wooden Shield', 'itm_shield_wooden',1,'workbench', 2, '{"timeSec":40}'),
('rcp_rope_bundle',        'Weave Rope (50ft)',   'itm_rope',        1, 'workbench', 2, '{"timeSec":45}'),
('rcp_splint_kit',         'Assemble Splint Kit', 'itm_splint',      1, 'workbench', 3, '{"timeSec":30}'),
('rcp_repair_kit_cloth',   'Assemble Cloth Repair Kit', 'itm_repair_kit_cloth', 1, 'workbench', 2, '{"timeSec":25,"uses":3}');

INSERT OR IGNORE INTO recipe_ingredients (recipe_id, item_def_id, qty) VALUES
('rcp_campfire_bread', 'itm_wood', 1),
('rcp_campfire_bread', 'itm_bread', 1),

('rcp_campfire_jerky', 'itm_meat', 1),

('rcp_bandage', 'itm_cloth', 1),
('rcp_bandage', 'itm_leather', 1),

('rcp_small_potion', 'itm_healing_herb', 2),
('rcp_small_potion', 'itm_mint_leaf', 1),

('rcp_medium_potion', 'itm_healing_herb', 3),
('rcp_medium_potion', 'itm_sunpetal', 2),

('rcp_stamina_draught', 'itm_mint_leaf', 3),
('rcp_stamina_draught', 'itm_healing_herb', 1),

('rcp_iron_ingot', 'itm_iron_ore', 2),

('rcp_leather_strap', 'itm_leather', 1),

('rcp_arrow_bundle', 'itm_wood', 2),
('rcp_arrow_bundle', 'itm_stone', 1),

('rcp_bolt_bundle', 'itm_wood', 2),
('rcp_bolt_bundle', 'itm_iron_ingot', 1),

('rcp_iron_sword', 'itm_iron_ingot', 2),
('rcp_iron_sword', 'itm_wood', 1),

('rcp_leather_cap', 'itm_leather', 2),
('rcp_leather_cap', 'itm_cloth', 1),

('rcp_leather_vest', 'itm_leather', 4),
('rcp_leather_vest', 'itm_cloth', 2),

('rcp_repair_kit_iron', 'itm_iron_ingot', 2),
('rcp_repair_kit_iron', 'itm_wax', 2),
('rcp_repair_kit_iron', 'itm_cloth', 1),

('rcp_repair_kit_leather', 'itm_leather_strap', 3),
('rcp_repair_kit_leather', 'itm_wax', 2),
('rcp_repair_kit_leather', 'itm_cloth', 1);



/* =========================================================
   AI item hints (expanded)
   ========================================================= */

INSERT OR IGNORE INTO ai_item_hints (item_def_id, role, priority, hint_json) VALUES
('itm_bandage', 'healing', 80, '{"useWhen":{"hpBelowPct":60}}'),
('itm_small_potion', 'healing', 95, '{"useWhen":{"hpBelowPct":40}}'),
('itm_medium_potion', 'healing', 98, '{"useWhen":{"hpBelowPct":25}}'),
('itm_stamina_draught', 'stamina', 85, '{"useWhen":{"staminaBelowPct":40}}'),

('itm_arrow', 'ammo', 60, '{"keepAtLeast":20,"forWeaponAmmo":"ammo:arrow"}'),
('itm_bolt', 'ammo', 60, '{"keepAtLeast":20,"forWeaponAmmo":"ammo:bolt"}'),
('itm_pebble', 'ammo', 40, '{"keepAtLeast":30,"forWeaponAmmo":"ammo:pebble"}'),

('itm_repair_kit_iron', 'repair', 75, '{"useWhen":{"durabilityBelowPct":50},"targets":["material:iron"]}'),
('itm_repair_kit_leather', 'repair', 75, '{"useWhen":{"durabilityBelowPct":50},"targets":["material:leather"]}'),

('itm_torch', 'travel', 60, '{"useWhen":{"dark":true}}'),
('itm_glow_pebble', 'travel', 70, '{"useWhen":{"dark":true}}');



/* =========================================================
   Buildings + shops + stock rules
   ========================================================= */

INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id) VALUES
('bld_brindlewick_general', 'set_brindlewick', 'Brindlewick General Goods', 'general', NULL, 'faction_merchants_guild'),
('bld_brindlewick_smith',   'set_brindlewick', 'Hearth & Hammer Smithy',   'blacksmith', 'forge', 'faction_iron_oath'),
('bld_brindlewick_tavern',  'set_brindlewick', 'The Warm Kettle',          'tavern', 'campfire', NULL),

('bld_emberhold_smith',     'set_emberhold',   'Emberhold Forgeworks',     'blacksmith', 'forge', 'faction_iron_oath'),
('bld_emberhold_alchemy',   'set_emberhold',   'Cinderleaf Alchemy',       'alchemist', 'alchemy', NULL),
('bld_emberhold_workshop',  'set_emberhold',   'Tinker’s Corner',          'workshop', 'workbench', NULL);

INSERT OR IGNORE INTO shops (id, settlement_id, building_id, name, shop_type, buy_mult, sell_mult, restock_minutes, last_restock_at) VALUES
('shop_brindlewick_general', 'set_brindlewick', 'bld_brindlewick_general', 'Brindlewick General', 'general', 0.5, 1.0, 60, 0),
('shop_brindlewick_smith',   'set_brindlewick', 'bld_brindlewick_smith',   'Hearth & Hammer',     'blacksmith', 0.45, 1.15, 90, 0),
('shop_brindlewick_tavern',  'set_brindlewick', 'bld_brindlewick_tavern',  'The Warm Kettle',     'tavern', 0.4, 1.1, 45, 0),

('shop_emberhold_smith',     'set_emberhold',   'bld_emberhold_smith',     'Emberhold Forgeworks', 'blacksmith', 0.45, 1.2, 90, 0),
('shop_emberhold_alchemy',   'set_emberhold',   'bld_emberhold_alchemy',   'Cinderleaf Alchemy',   'alchemist', 0.5, 1.25, 90, 0);

INSERT OR IGNORE INTO shop_stock_rules (shop_id, item_def_id, min_qty, max_qty, weight, price_mult) VALUES
('shop_brindlewick_general', 'itm_bread', 4, 12, 30, 1.0),
('shop_brindlewick_general', 'itm_wood',  6, 20, 20, 1.0),
('shop_brindlewick_general', 'itm_jerky', 2, 10, 25, 1.0),

('shop_brindlewick_smith', 'itm_iron_sword', 0, 2, 12, 1.1),
('shop_brindlewick_smith', 'itm_leather_cap', 1, 3, 18, 1.0),
('shop_brindlewick_smith', 'itm_repair_kit_iron', 0, 2, 10, 1.2),

('shop_emberhold_alchemy', 'itm_healing_herb', 3, 12, 25, 1.0),
('shop_emberhold_alchemy', 'itm_small_potion', 0, 4, 12, 1.2),
('shop_emberhold_alchemy', 'itm_medium_potion', 0, 2, 6,  1.35),
('shop_emberhold_alchemy', 'itm_bandage',      1, 8, 18, 1.1);

INSERT OR IGNORE INTO shop_stock_tag_rules (shop_id, tag_id, min_qty, max_qty, weight, price_mult) VALUES
('shop_brindlewick_general', 'item:food',     2, 12, 25, 1.0),
('shop_brindlewick_general', 'item:tool',     1,  6, 18, 1.0),
('shop_brindlewick_general', 'item:ammo',     5, 40, 18, 1.0),
('shop_brindlewick_general', 'item:resource', 3, 25, 20, 1.0),

('shop_brindlewick_smith',   'item:weapon',   0,  3, 15, 1.1),
('shop_brindlewick_smith',   'item:armor',    0,  3, 15, 1.05),
('shop_brindlewick_smith',   'use:repair',    0,  4, 12, 1.15),

('shop_emberhold_alchemy',   'ingredient:herb',2, 18, 30, 1.0),
('shop_emberhold_alchemy',   'use:heal',       1,  8, 18, 1.2),
('shop_emberhold_alchemy',   'use:stamina',    0,  6, 14, 1.15);



/* =========================================================
   NPC seeds
   ========================================================= */

INSERT OR IGNORE INTO npcs (id, settlement_id, building_id, name, role, personality_tags, dialogue_seed) VALUES
('npc_mara_goods',     'set_brindlewick', 'bld_brindlewick_general', 'Mara Goodwell', 'merchant', '["kind","chatty","rumor_spreader"]',
 'Always knows what’s missing in town—and who caused it.'),
('npc_garrick_smith',  'set_brindlewick', 'bld_brindlewick_smith',   'Garrick Emberhand', 'blacksmith', '["gruff","honorable","craft_proud"]',
 'Respects brave kids. Hates sloppy work. Loves good stories.'),
('npc_sella_inn',      'set_brindlewick', 'bld_brindlewick_tavern',  'Sella Warmkettle', 'innkeeper', '["motherly","sharp","protective"]',
 'Feeds heroes and quietly watches for trouble.'),
('npc_orrin_alch',     'set_emberhold',   'bld_emberhold_alchemy',   'Orrin Cinderleaf', 'alchemist', '["curious","quirky","helpful"]',
 'Brews potions and trades secrets for interesting ingredients.');


/* =========================================================
   Loot tables + attachments (alive exploration foundation)
   ========================================================= */

INSERT OR IGNORE INTO loot_tables (id, name, roll_count, meta_json) VALUES
('lt_ruins_low',   'Ruins (Low)',   2, '{"theme":"ruins","tier":"low"}'),
('lt_cave_mid',    'Cave (Mid)',    3, '{"theme":"cave","tier":"mid"}'),
('lt_bandit_camp', 'Bandit Camp',   3, '{"theme":"camp","tier":"mid"}'),
('lt_shop_backroom','Shop Backroom',2, '{"theme":"shop","tier":"low"}');

-- Direct loot entries
INSERT OR IGNORE INTO loot_table_entries (loot_table_id, item_def_id, min_qty, max_qty, weight) VALUES
('lt_ruins_low', 'itm_coin_placeholder', 5, 25, 0);

-- Tag-based entries (these do the real work)
INSERT OR IGNORE INTO loot_table_tag_entries (loot_table_id, tag_id, min_qty, max_qty, weight) VALUES
('lt_ruins_low',   'item:resource',   1, 4, 30),
('lt_ruins_low',   'item:ammo',       5, 20, 18),
('lt_ruins_low',   'item:trinket',    1, 1, 6),
('lt_ruins_low',   'use:heal',        1, 2, 12),

('lt_cave_mid',    'item:resource',   2, 6, 28),
('lt_cave_mid',    'ingredient:herb', 1, 4, 22),
('lt_cave_mid',    'use:heal',        1, 2, 16),
('lt_cave_mid',    'use:stamina',     1, 2, 14),

('lt_bandit_camp', 'item:ammo',       10, 35, 30),
('lt_bandit_camp', 'item:tool',       1, 2, 10),
('lt_bandit_camp', 'use:repair',      1, 2, 12),
('lt_bandit_camp', 'use:heal',        1, 2, 16),

('lt_shop_backroom','item:tool',      1, 2, 18),
('lt_shop_backroom','use:repair',     0, 1, 10),
('lt_shop_backroom','item:resource',  1, 3, 20);

-- Attach loot tables to POIs
INSERT OR IGNORE INTO poi_loot (poi_id, loot_table_id, respawn_minutes, last_looted_at) VALUES
('poi_blackbarrow_ruins', 'lt_ruins_low', 180, 0),
('poi_mossjaw_cave',      'lt_cave_mid',  240, 0),
('poi_roadside_bandits',  'lt_bandit_camp', 240, 0),
('poi_sablecliff_camp',   'lt_bandit_camp', 240, 0);

-- Attach loot tables to buildings (fun “back room” loot)
INSERT OR IGNORE INTO building_loot (building_id, loot_table_id, respawn_minutes, last_looted_at) VALUES
('bld_brindlewick_general', 'lt_shop_backroom', 240, 0),
('bld_emberhold_alchemy',   'lt_shop_backroom', 240, 0);



COMMIT;
