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

-- RESOURCES / COMPONENTS
('itm_wood',      'Wood',      'resource', NULL, 'common', 1, 50, 1, 0.5, 0, '{"tags":["item:resource","material:wood"]}'),
('itm_stone',     'Stone',     'resource', NULL, 'common', 1, 50, 1, 0.7, 0, '{"tags":["item:resource","material:stone"]}'),
('itm_iron_ore',  'Iron Ore',  'resource', NULL, 'common', 1, 50, 3, 0.8, 0, '{"tags":["item:resource","material:iron"]}'),
('itm_leather',   'Leather',   'resource', NULL, 'common', 1, 50, 2, 0.4, 0, '{"tags":["item:resource","material:leather"]}'),
('itm_cloth',     'Cloth',     'resource', NULL, 'common', 1, 50, 2, 0.3, 0, '{"tags":["item:resource","material:cloth"]}'),
('itm_meat',      'Meat',      'resource', NULL, 'common', 1, 20, 3, 0.4, 0, '{"tags":["item:resource","ingredient:meat"]}'),

-- NEW: repair components
('itm_iron_ingot', 'Iron Ingot', 'component', NULL, 'common', 1, 50, 6, 0.7, 0, '{"tags":["item:component","material:iron","use:repair"]}'),
('itm_leather_strap','Leather Strap','component',NULL,'common',1,50,4,0.2,0,'{"tags":["item:component","material:leather","use:repair"]}'),
('itm_wax',        'Wax',       'component', NULL, 'common', 1, 50, 2, 0.1, 0, '{"tags":["item:component","use:repair"]}'),

-- FOOD / CONSUMABLES
('itm_bread',     'Bread',     'consumable', NULL, 'common', 1, 10, 1, 0.2, 0, '{"heal":2,"tags":["item:food","use:heal"]}'),
('itm_jerky',     'Jerky',     'consumable', NULL, 'common', 1, 10, 2, 0.2, 0, '{"stamina":2,"tags":["item:food","use:stamina"]}'),
('itm_bandage',   'Bandage',   'consumable', NULL, 'common', 1, 10, 5, 0.2, 0, '{"heal":5,"tags":["use:heal"]}'),

-- NEW: potion tiering
('itm_small_potion','Small Potion','consumable',NULL,'uncommon',1,5,18,0.5,0,'{"heal":10,"tags":["use:heal"]}'),
('itm_medium_potion','Medium Potion','consumable',NULL,'rare',1,3,45,0.6,0,'{"heal":25,"tags":["use:heal"]}'),
('itm_stamina_draught','Stamina Draught','consumable',NULL,'uncommon',1,5,20,0.5,0,'{"stamina":12,"tags":["use:stamina"]}'),

-- TOOLS
('itm_torch',     'Torch',     'tool', NULL, 'common', 1, 5, 1, 0.6, 0, '{"light":1,"tags":["item:tool","use:light"]}'),

-- REPAIR KITS
('itm_repair_kit_iron',    'Metal Repair Kit',   'tool',NULL,'uncommon',1,10,22,0.8,0,'{"repair":{"amount":30,"targets":["material:iron"],"uses":3},"tags":["item:tool","use:repair","repair:iron"]}'),
('itm_repair_kit_leather', 'Leather Repair Kit', 'tool',NULL,'uncommon',1,10,18,0.6,0,'{"repair":{"amount":30,"targets":["material:leather"],"uses":3},"tags":["item:tool","use:repair","repair:leather"]}'),

-- AMMO
('itm_arrow',     'Arrow',     'ammo', NULL, 'common', 1, 50, 1, 0.1, 0, '{"tags":["item:ammo","ammo:arrow"]}'),
('itm_bolt',      'Bolt',      'ammo', NULL, 'common', 1, 50, 1, 0.1, 0, '{"tags":["item:ammo","ammo:bolt"]}'),
('itm_pebble',    'Pebble',    'ammo', NULL, 'common', 1, 99, 1, 0.1, 0, '{"tags":["item:ammo","ammo:pebble"]}'),

-- WEAPONS
('itm_wooden_club',   'Wooden Club',    'weapon', 'mainhand','common',0,1,4,2.5,40,'{"damage":2,"tags":["item:weapon","material:wood"]}'),
('itm_training_sword','Training Sword', 'weapon', 'mainhand','common',0,1,6,2.0,45,'{"damage":2,"tags":["item:weapon"]}'),
('itm_iron_dagger',   'Iron Dagger',    'weapon', 'offhand', 'common',0,1,14,1.0,65,'{"damage":3,"tags":["item:weapon","material:iron"]}'),
('itm_iron_sword',    'Iron Sword',     'weapon', 'mainhand','common',0,1,25,3.5,80,'{"damage":5,"tags":["item:weapon","material:iron"]}'),
('itm_spear',         'Spear',          'weapon', 'mainhand','common',0,1,20,3.0,75,'{"damage":4,"reach":1,"tags":["item:weapon","material:wood"]}'),
('itm_short_bow',     'Short Bow',      'weapon', 'mainhand','uncommon',0,1,20,2.0,70,'{"damage":4,"ranged":1,"ammo":"ammo:arrow","tags":["item:weapon","material:wood"]}'),
('itm_crossbow',      'Crossbow',       'weapon', 'mainhand','uncommon',0,1,35,4.0,90,'{"damage":6,"ranged":1,"ammo":"ammo:bolt","tags":["item:weapon","material:wood","material:iron"]}'),

-- ARMOR
('itm_cloth_cap',     'Cloth Cap',      'armor','helmet','common',0,1,4,0.4,30,'{"armor":1,"tags":["item:armor","material:cloth"]}'),
('itm_cloth_tunic',   'Cloth Tunic',    'armor','torso','common',0,1,8,1.5,50,'{"armor":1,"tags":["item:armor","material:cloth"]}'),
('itm_leather_cap',   'Leather Cap',    'armor','helmet','common',0,1,12,1.2,60,'{"armor":1,"tags":["item:armor","material:leather"]}'),
('itm_leather_vest',  'Leather Vest',   'armor','torso','common',0,1,22,4.0,90,'{"armor":2,"tags":["item:armor","material:leather"]}'),

-- TRINKETS
('itm_lucky_coin',    'Lucky Coin',     'trinket',NULL,'uncommon',0,1,15,0.1,0,'{"luck":1,"tags":["item:trinket"]}'),
('itm_glow_pebble',   'Glow Pebble',    'trinket',NULL,'common',0,1,8,0.2,0,'{"light":1,"tags":["item:trinket","use:light"]}'),
('itm_brave_badge',   'Brave Badge',    'trinket',NULL,'uncommon',0,1,20,0.2,0,'{"brave":1,"tags":["item:trinket"]}'),

-- HERBS
('itm_healing_herb',  'Healing Herb',   'resource',NULL,'common',1,20,4,0.1,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"]}'),
('itm_mint_leaf',     'Mint Leaf',      'resource',NULL,'common',1,30,2,0.05,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"]}'),
('itm_sunpetal',      'Sunpetal',       'resource',NULL,'uncommon',1,20,6,0.05,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"]}');



/* =========================================================
   Tag links (query-friendly)
   ========================================================= */

INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_wood', 'material:wood'),
('itm_stone', 'material:stone'),
('itm_iron_ore', 'material:iron'),
('itm_leather', 'material:leather'),
('itm_cloth', 'material:cloth'),

('itm_iron_ingot','material:iron'),
('itm_leather_strap','material:leather'),

('itm_bread', 'item:food'),
('itm_jerky', 'item:food'),

('itm_iron_sword', 'item:weapon'),
('itm_iron_dagger', 'item:weapon'),
('itm_short_bow', 'item:weapon'),
('itm_crossbow', 'item:weapon'),

('itm_leather_cap', 'item:armor'),
('itm_leather_vest', 'item:armor'),
('itm_cloth_cap', 'item:armor'),
('itm_cloth_tunic', 'item:armor'),

('itm_healing_herb', 'ingredient:herb'),
('itm_mint_leaf', 'ingredient:herb'),
('itm_sunpetal', 'ingredient:herb'),
('itm_meat', 'ingredient:meat'),

('itm_arrow', 'item:ammo'),
('itm_bolt', 'item:ammo'),
('itm_pebble', 'item:ammo'),

('itm_glow_pebble', 'item:trinket'),
('itm_lucky_coin', 'item:trinket'),

('itm_repair_kit_iron', 'use:repair'),
('itm_repair_kit_leather', 'use:repair'),
('itm_iron_ingot', 'use:repair'),
('itm_leather_strap', 'use:repair'),

('itm_bandage', 'use:heal'),
('itm_small_potion', 'use:heal'),
('itm_medium_potion', 'use:heal'),
('itm_stamina_draught', 'use:stamina');



/* =========================================================
   Recipes (expanded)
   ========================================================= */

INSERT OR IGNORE INTO recipes (id, name, output_item_def_id, output_qty, station, difficulty, meta_json) VALUES
('rcp_campfire_jerky',      'Dry Jerky',            'itm_jerky',       2, 'campfire', 1, '{"timeSec":20}'),
('rcp_campfire_bread',      'Bake Bread',           'itm_bread',       2, 'campfire', 1, '{"timeSec":20}'),

('rcp_bandage',             'Make Bandage',         'itm_bandage',     1, 'workbench', 1, '{"timeSec":15}'),
('rcp_small_potion',        'Brew Small Potion',    'itm_small_potion',1, 'alchemy',    2, '{"timeSec":25}'),
('rcp_medium_potion',       'Brew Medium Potion',   'itm_medium_potion',1,'alchemy',    4, '{"timeSec":45}'),
('rcp_stamina_draught',     'Brew Stamina Draught', 'itm_stamina_draught',1,'alchemy',  3, '{"timeSec":35}'),

('rcp_iron_ingot',          'Smelt Iron Ingot',     'itm_iron_ingot',  1, 'forge',      2, '{"timeSec":25}'),
('rcp_leather_strap',       'Cut Leather Straps',   'itm_leather_strap',2,'workbench',  1, '{"timeSec":15}'),

('rcp_arrow_bundle',        'Make Arrows',          'itm_arrow',       15,'workbench',  2, '{"timeSec":25}'),
('rcp_bolt_bundle',         'Make Bolts',           'itm_bolt',        12,'workbench',  2, '{"timeSec":25}'),

('rcp_iron_sword',          'Forge Iron Sword',     'itm_iron_sword',  1, 'forge',      3, '{"timeSec":35}'),
('rcp_leather_cap',         'Stitch Leather Cap',   'itm_leather_cap', 1, 'workbench',  2, '{"timeSec":25}'),
('rcp_leather_vest',        'Stitch Leather Vest',  'itm_leather_vest',1, 'workbench',  3, '{"timeSec":35}'),

('rcp_repair_kit_iron',     'Assemble Metal Repair Kit', 'itm_repair_kit_iron', 1, 'workbench', 3, '{"timeSec":30,"uses":3}'),
('rcp_repair_kit_leather',  'Assemble Leather Repair Kit','itm_repair_kit_leather',1,'workbench',3,'{"timeSec":30,"uses":3}');

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
