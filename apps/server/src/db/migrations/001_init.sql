BEGIN;
PRAGMA defer_foreign_keys = ON;
PRAGMA foreign_keys = OFF;

-- =========================================================
-- 001_init.sql (Fixed / Unified)
-- - Creates core auth + character tables
-- - Creates item_defs + item_instances (replaces old items table)
-- - Creates world tables (factions, settlements, POIs, buildings, NPCs)
-- - Creates shops + crafting + quests + loot + logs
-- - Seeds starter data
-- =========================================================


/* =========================================================
   0) Accounts / Sessions
   ========================================================= */

CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);


/* =========================================================
   1) Characters (with HP/Stamina/Carry)
   ========================================================= */

CREATE TABLE IF NOT EXISTS characters (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  name TEXT NOT NULL,
  race TEXT NOT NULL,
  class TEXT NOT NULL,
  background TEXT NOT NULL,
  personality INTEGER NOT NULL DEFAULT 50,
  level INTEGER NOT NULL DEFAULT 1,
  gold INTEGER NOT NULL DEFAULT 0,

  hp INTEGER NOT NULL DEFAULT 30,
  hp_max INTEGER NOT NULL DEFAULT 30,
  stamina INTEGER NOT NULL DEFAULT 30,
  stamina_max INTEGER NOT NULL DEFAULT 30,

  carry_capacity REAL NOT NULL DEFAULT 120.0,

  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS saves (
  character_id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  state_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);


/* =========================================================
   2) Item catalog vs instances (NEW SYSTEM)
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


/* =========================================================
   3) Tags + tag mapping (Query-friendly)
   ========================================================= */

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


/* =========================================================
   4) Equipment (references item_instances now)
   ========================================================= */

CREATE TABLE IF NOT EXISTS equipment (
  character_id TEXT NOT NULL,
  slot TEXT NOT NULL,
  item_instance_id TEXT NULL,
  PRIMARY KEY (character_id, slot),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (item_instance_id) REFERENCES item_instances(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_equipment_instance ON equipment(item_instance_id);


/* =========================================================
   5) Containers (Inventory QoL)
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
   6) World data: factions, settlements, POIs, buildings, NPCs
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
   7) Shops + stock rules
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
   8) Crafting system
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
   9) Quests & objectives
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
   10) World events + AI item hints
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

CREATE TABLE IF NOT EXISTS ai_item_hints (
  item_def_id TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 50,
  hint_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);


/* =========================================================
   11) Reputation + Skills + Craft/Repair logs + Loot
   ========================================================= */

CREATE TABLE IF NOT EXISTS character_faction_rep (
  character_id TEXT NOT NULL,
  faction_id TEXT NOT NULL,
  rep INTEGER NOT NULL DEFAULT 0,
  last_updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (character_id, faction_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (faction_id) REFERENCES factions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_char_faction_rep_char ON character_faction_rep(character_id);

CREATE TABLE IF NOT EXISTS skills (
  id TEXT PRIMARY KEY,
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

CREATE TABLE IF NOT EXISTS crafting_log (
  id TEXT PRIMARY KEY,
  character_id TEXT NOT NULL,
  recipe_id TEXT NOT NULL,
  success INTEGER NOT NULL DEFAULT 1,
  notes TEXT NOT NULL DEFAULT '',
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_crafting_log_char ON crafting_log(character_id);

CREATE TABLE IF NOT EXISTS repair_log (
  id TEXT PRIMARY KEY,
  character_id TEXT NOT NULL,
  item_instance_id TEXT NOT NULL,
  repair_item_def_id TEXT NOT NULL,
  durability_before INTEGER NOT NULL,
  durability_after INTEGER NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (item_instance_id) REFERENCES item_instances(id) ON DELETE CASCADE,
  FOREIGN KEY (repair_item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_repair_log_char ON repair_log(character_id);

CREATE TABLE IF NOT EXISTS loot_tables (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  roll_count INTEGER NOT NULL DEFAULT 1,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

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
   12) Seed data: factions, settlements, POIs, tags, skills
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
('material:mithral', 'Mithral'),
('material:adamantine', 'Adamantine'),

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
('item:medical', 'Medical'),
('item:potion', 'Potion'),

('ingredient:herb', 'Herb'),
('ingredient:meat', 'Meat'),

('use:heal', 'Healing'),
('use:stamina', 'Stamina'),
('use:light', 'Light'),
('use:repair', 'Repair'),
('use:craft', 'Crafting Use'),

('ammo:arrow', 'Arrow Ammo'),
('ammo:bolt', 'Bolt Ammo'),
('ammo:pebble', 'Pebble Ammo'),

('repair:iron', 'Repairs Iron Gear'),
('repair:leather', 'Repairs Leather Gear'),
('repair:cloth', 'Repairs Cloth Gear'),

('rarity:common', 'Common'),
('rarity:uncommon', 'Uncommon'),
('rarity:rare', 'Rare'),
('rarity:epic', 'Epic'),
('rarity:legendary', 'Legendary');

INSERT OR IGNORE INTO skills (id, name, description, meta_json) VALUES
('skill_crafting', 'Crafting', 'Make gear, tools, and supplies more efficiently.', '{"affects":["forge","workbench","alchemy","campfire"]}'),
('skill_survival', 'Survival', 'Travel, camp, hunt, and avoid danger.', '{"affects":["encounters","food","camping"]}'),
('skill_diplomacy', 'Diplomacy', 'Better deals and better outcomes with factions.', '{"affects":["prices","rep_gains"]}'),
('skill_combat', 'Combat', 'Stronger attacks and smarter fighting.', '{"affects":["damage","stamina"]}');


/* =========================================================
   13) Item defs seed (includes coins so loot works)
   ========================================================= */

INSERT OR IGNORE INTO item_defs
(id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json) VALUES
('itm_coin', 'Coins', 'resource', NULL, 'common', 1, 9999, 1, 0.0, 0, '{"tags":["item:resource"],"flavor":"Clinks with possibility."}'),

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

('itm_bread',       'Bread Loaf',            'consumable', NULL, 'common', 1, 10, 1, 0.2, 0, '{"heal":2,"tags":["item:food","use:heal"],"flavor":"Warm enough to make you brave."}'),
('itm_jerky',       'Jerky Strip',           'consumable', NULL, 'common', 1, 10, 2, 0.2, 0, '{"stamina":2,"tags":["item:food","use:stamina"],"flavor":"Dry, salty, and reliable."}'),
('itm_rations',     'Travel Rations',        'consumable', NULL, 'common', 1, 10, 5, 0.6, 0, '{"stamina":4,"tags":["item:food","use:stamina"],"flavor":"Hardtack, nuts, and dried fruit—adventurer fuel."}'),
('itm_cheese',      'Cheese Wheel',          'consumable', NULL, 'common', 1, 5,  4, 0.7, 0, '{"heal":3,"tags":["item:food","use:heal"],"flavor":"Smells strong. Tastes stronger."}'),
('itm_honey',       'Jar of Honey',          'consumable', NULL, 'uncommon',1, 5,  8, 0.8, 0, '{"heal":4,"tags":["item:food","use:heal"],"flavor":"Sweet gold—good for morale and sore throats."}'),
('itm_water_flask', 'Waterskin',             'consumable', NULL, 'common', 1, 3,  2, 0.9, 0, '{"stamina":2,"tags":["item:food","use:stamina"],"flavor":"Cool water on a dusty road."}'),

('itm_bandage',     'Bandage Roll',          'consumable', NULL, 'common', 1, 10, 5, 0.2, 0, '{"heal":5,"tags":["use:heal","item:medical"],"flavor":"Clean cloth strips—wrap it tight."}'),
('itm_splint',      'Splint Kit',            'consumable', NULL, 'uncommon',1, 5,  12,0.6, 0, '{"heal":8,"tags":["use:heal","item:medical"],"flavor":"Wood, cloth, and know-how in a pouch."}'),

('itm_small_potion',    'Potion of Healing (Small)',  'consumable', NULL, 'uncommon', 1, 5,  18, 0.5, 0, '{"heal":10,"tags":["use:heal","item:potion"],"flavor":"A red swirl that tastes like cinnamon."}'),
('itm_medium_potion',   'Potion of Healing (Medium)', 'consumable', NULL, 'rare',     1, 3,  45, 0.6, 0, '{"heal":25,"tags":["use:heal","item:potion"],"flavor":"A deeper red—warmth spreads fast."}'),
('itm_stamina_draught', 'Stamina Draught',            'consumable', NULL, 'uncommon', 1, 5,  20, 0.5, 0, '{"stamina":12,"tags":["use:stamina","item:potion"],"flavor":"Tastes like mint and thunder."}'),
('itm_focus_tonic',     'Focus Tonic',                'consumable', NULL, 'rare',     1, 3,  40, 0.4, 0, '{"focus":1,"tags":["use:focus","item:potion"],"flavor":"Sharpens your thoughts like a whetstone."}'),

('itm_torch',         'Torch',               'tool', NULL, 'common',   1,  5,  1, 0.6, 0, '{"light":1,"tags":["item:tool","use:light"],"flavor":"A simple flame that makes shadows behave."}'),
('itm_flint_steel',   'Flint & Steel',       'tool', NULL, 'common',   1,  1,  5, 0.2, 0, '{"tags":["item:tool","use:fire"],"flavor":"Sparks on demand."}'),
('itm_rope',          'Rope (50 ft)',        'tool', NULL, 'common',   1,  1,  10,1.0, 0, '{"tags":["item:tool","use:climb"],"flavor":"Hemp rope with a trustworthy bite."}'),
('itm_lockpicks',     'Lockpicks (Simple)',  'tool', NULL, 'uncommon', 1,  1,  25,0.1, 0, '{"tags":["item:tool","use:lockpick"],"flavor":"For doors that think they’re clever."}'),

('itm_repair_kit_iron',    'Metal Repair Kit',    'tool', NULL, 'uncommon', 1, 10, 22, 0.8, 0, '{"repair":{"amount":30,"targets":["material:iron"],"uses":3},"tags":["item:tool","use:repair","repair:iron"],"flavor":"Rivets, oil, and a tiny hammer."}'),
('itm_repair_kit_leather', 'Leather Repair Kit',  'tool', NULL, 'uncommon', 1, 10, 18, 0.6, 0, '{"repair":{"amount":30,"targets":["material:leather"],"uses":3},"tags":["item:tool","use:repair","repair:leather"],"flavor":"Needle, waxed thread, and patches."}'),
('itm_repair_kit_cloth',   'Cloth Repair Kit',    'tool', NULL, 'common',   1, 10, 12, 0.4, 0, '{"repair":{"amount":20,"targets":["material:cloth"],"uses":3},"tags":["item:tool","use:repair","repair:cloth"],"flavor":"Thread and a little patience."}'),

('itm_arrow',   'Arrow',   'ammo', NULL, 'common', 1, 50, 1, 0.1, 0, '{"tags":["item:ammo","ammo:arrow"],"flavor":"Straight shaft, sharp promise."}'),
('itm_bolt',    'Bolt',    'ammo', NULL, 'common', 1, 50, 1, 0.1, 0, '{"tags":["item:ammo","ammo:bolt"],"flavor":"Short and mean."}'),
('itm_pebble',  'Pebble',  'ammo', NULL, 'common', 1, 99, 1, 0.1, 0, '{"tags":["item:ammo","ammo:pebble"],"flavor":"Nature’s cheapest projectile."}'),

('itm_wooden_club',    'Wooden Club',    'weapon','mainhand','common',   0, 1,  4, 2.5, 40, '{"damage":2,"tags":["item:weapon","material:wood"],"flavor":"Simple, honest bonking."}'),
('itm_training_sword', 'Training Sword', 'weapon','mainhand','common',   0, 1,  6, 2.0, 45, '{"damage":2,"tags":["item:weapon"],"flavor":"Blunt edge—perfect for practice duels."}'),
('itm_iron_dagger',    'Iron Dagger',    'weapon','offhand','common',    0, 1, 14, 1.0, 65, '{"damage":3,"tags":["item:weapon","material:iron"],"flavor":"A quiet blade for quick problems."}'),
('itm_iron_sword',     'Iron Sword',     'weapon','mainhand','common',   0, 1, 25, 3.5, 80, '{"damage":5,"tags":["item:weapon","material:iron"],"flavor":"A classic adventurer’s companion."}'),

('itm_cloth_cap',    'Cloth Cap',      'armor','helmet','common', 0,1, 4, 0.4,30,'{"armor":1,"tags":["item:armor","material:cloth"],"flavor":"Keeps sun off and pride intact."}'),
('itm_cloth_tunic',  'Cloth Tunic',    'armor','torso','common',  0,1, 8, 1.5,50,'{"armor":1,"tags":["item:armor","material:cloth"],"flavor":"Better than fighting in pajamas."}'),
('itm_leather_cap',  'Leather Cap',    'armor','helmet','common', 0,1,12, 1.2,60,'{"armor":1,"tags":["item:armor","material:leather"],"flavor":"Smells like adventure and old rain."}'),
('itm_leather_vest', 'Leather Vest',   'armor','torso','common',  0,1,22, 4.0,90,'{"armor":2,"tags":["item:armor","material:leather"],"flavor":"Tough enough for brambles and bruises."}'),

('itm_healing_herb', 'Healing Herb',    'resource',NULL,'common',  1,20, 4,0.1,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"],"flavor":"Smells clean—like a sunny morning."}'),
('itm_mint_leaf',    'Mint Leaf',       'resource',NULL,'common',  1,30, 2,0.05,0,'{"tags":["item:resource","ingredient:herb","station:alchemy"],"flavor":"Fresh enough to wake a sleepy wizard."}');


/* =========================================================
   14) Minimal tag links used by shop/loot systems
   ========================================================= */

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

('itm_bread', 'item:food'),
('itm_jerky', 'item:food'),
('itm_rations', 'item:food'),
('itm_cheese', 'item:food'),
('itm_honey', 'item:food'),
('itm_water_flask', 'item:food'),

('itm_wooden_club', 'item:weapon'),
('itm_training_sword', 'item:weapon'),
('itm_iron_dagger', 'item:weapon'),
('itm_iron_sword', 'item:weapon'),

('itm_cloth_cap', 'item:armor'),
('itm_cloth_tunic', 'item:armor'),
('itm_leather_cap', 'item:armor'),
('itm_leather_vest', 'item:armor'),

('itm_torch', 'item:tool'),
('itm_flint_steel', 'item:tool'),
('itm_rope', 'item:tool'),
('itm_lockpicks', 'item:tool'),

('itm_arrow', 'item:ammo'),
('itm_bolt', 'item:ammo'),
('itm_pebble', 'item:ammo'),

('itm_healing_herb', 'ingredient:herb'),
('itm_mint_leaf', 'ingredient:herb');


/* =========================================================
   15) Recipes (minimal + fixed output_qty types)
   ========================================================= */

INSERT OR IGNORE INTO recipes (id, name, output_item_def_id, output_qty, station, difficulty, meta_json) VALUES
('rcp_campfire_rations',   'Pack Travel Rations', 'itm_rations',     1, 'campfire',  1, '{"timeSec":30}'),
('rcp_focus_tonic',        'Distill Focus Tonic', 'itm_focus_tonic', 1, 'alchemy',   4, '{"timeSec":50}');

-- Note: You can re-add your full recipe list after this runs cleanly.


/* =========================================================
   16) Loot tables (minimal + fixed coin reference)
   ========================================================= */

INSERT OR IGNORE INTO loot_tables (id, name, roll_count, meta_json) VALUES
('lt_ruins_low',   'Ruins (Low)',   2, '{"theme":"ruins","tier":"low"}');

INSERT OR IGNORE INTO loot_table_entries (loot_table_id, item_def_id, min_qty, max_qty, weight) VALUES
('lt_ruins_low', 'itm_coin', 5, 25, 15);

INSERT OR IGNORE INTO loot_table_tag_entries (loot_table_id, tag_id, min_qty, max_qty, weight) VALUES
('lt_ruins_low', 'item:resource', 1, 4, 30),
('lt_ruins_low', 'item:ammo',     5, 20, 18);


/* =========================================================
   17) (Optional) If you want auto-create tags from mapping
   =========================================================
   I recommend NOT doing this. Seed tags explicitly instead.
   But if you insist, THIS is the correct version:

CREATE TRIGGER IF NOT EXISTS trg_autocreate_tags_from_item_def_tags
BEFORE INSERT ON item_def_tags
FOR EACH ROW
BEGIN
  INSERT OR IGNORE INTO tags (id, label) VALUES (NEW.tag_id, NEW.tag_id);
END;
*/


COMMIT;
PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;
