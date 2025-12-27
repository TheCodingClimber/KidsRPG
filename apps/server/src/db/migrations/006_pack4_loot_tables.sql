PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   4.3 LOOT TABLE SYSTEM (THEME + DANGER + TAG BASED)
   ========================================================= */

-- Master loot tables
CREATE TABLE IF NOT EXISTS loot_tables (
  id TEXT PRIMARY KEY,            -- loot_bandit_basic
  name TEXT NOT NULL,
  theme TEXT NOT NULL,            -- bandit/undead/beast/ruins/mountain/general
  danger_min INTEGER NOT NULL DEFAULT 1,
  danger_max INTEGER NOT NULL DEFAULT 100,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

-- Loot entries (can be item OR tag based)
CREATE TABLE IF NOT EXISTS loot_table_entries (
  id TEXT PRIMARY KEY,            -- lte_xxx
  loot_table_id TEXT NOT NULL,
  item_def_id TEXT NULL,
  tag_id TEXT NULL,               -- allow "any herb", "any trinket"
  weight INTEGER NOT NULL DEFAULT 10,
  min_qty INTEGER NOT NULL DEFAULT 1,
  max_qty INTEGER NOT NULL DEFAULT 1,
  rarity_bias INTEGER NOT NULL DEFAULT 0, -- -2..+2
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id),
  FOREIGN KEY (tag_id) REFERENCES tags(id)
);

CREATE INDEX IF NOT EXISTS idx_loot_entries_table ON loot_table_entries(loot_table_id);

-- POI → loot table mapping
CREATE TABLE IF NOT EXISTS poi_loot_profiles (
  poi_id TEXT PRIMARY KEY,
  loot_table_id TEXT NOT NULL,
  rolls INTEGER NOT NULL DEFAULT 2,
  FOREIGN KEY (poi_id) REFERENCES pois(id) ON DELETE CASCADE,
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id)
);

/* =========================================================
   4.3A TRINKETS (FUN, NON-COMBAT, KID-DELIGHT ITEMS)
   ========================================================= */

INSERT OR IGNORE INTO item_defs
(id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json)
VALUES
('itm_trinket_lucky_coin','Lucky Coin','trinket','trinket','uncommon',0,1,25,0.1,0,'{"luck":1,"tags":["item:trinket"]}'),
('itm_trinket_glass_beetle','Glass Beetle','trinket','trinket','common',0,1,10,0.2,0,'{"curio":1}'),
('itm_trinket_ancient_key','Ancient Key','trinket','trinket','rare',0,1,45,0.1,0,'{"unlock_bonus":1}'),
('itm_trinket_story_charm','Story Charm','trinket','trinket','epic',0,1,120,0.2,0,'{"lore":1,"dialogue_bonus":1}'),
('itm_trinket_moon_feather','Moon Feather','trinket','trinket','rare',0,1,60,0.1,0,'{"night_bonus":1}');

INSERT OR IGNORE INTO tags (id,label) VALUES
('item:trinket','Trinket');

/* =========================================================
   4.3B LOOT TABLE SEEDS (EXTENSIVE)
   ========================================================= */

INSERT OR IGNORE INTO loot_tables (id,name,theme,danger_min,danger_max) VALUES
('loot_bandit_basic','Bandit Camp Loot','bandit',1,40),
('loot_bandit_elite','Bandit Elite Cache','bandit',35,80),
('loot_beast_den','Beast Den','beast',1,60),
('loot_undead_ruins','Undead Ruins','undead',10,70),
('loot_ancient_ruins','Ancient Ruins','ruins',20,90),
('loot_mountain_cache','Mountain Cache','mountain',30,100),
('loot_general_travel','Travel Finds','general',1,100);

-- BANDIT BASIC
INSERT OR IGNORE INTO loot_table_entries
(id,loot_table_id,item_def_id,weight,min_qty,max_qty)
VALUES
('lte_bandit_bread','loot_bandit_basic','itm_bread',30,1,3),
('lte_bandit_jerky','loot_bandit_basic','itm_jerky',25,1,3),
('lte_bandit_torch','loot_bandit_basic','itm_torch',20,1,2),
('lte_bandit_weapon','loot_bandit_basic',NULL,15,1,1);

INSERT OR IGNORE INTO loot_table_entries
(id,loot_table_id,tag_id,weight)
VALUES
('lte_bandit_weapons_any','loot_bandit_basic','item:weapon',12),
('lte_bandit_trinket','loot_bandit_basic','item:trinket',5);

-- UNDEAD RUINS
INSERT OR IGNORE INTO loot_table_entries
(id,loot_table_id,tag_id,weight)
VALUES
('lte_undead_trinket','loot_undead_ruins','item:trinket',20),
('lte_undead_herb','loot_undead_ruins','item:resource',10);

INSERT OR IGNORE INTO loot_table_entries
(id,loot_table_id,item_def_id,weight)
VALUES
('lte_undead_coin','loot_undead_ruins','itm_trinket_lucky_coin',15),
('lte_undead_charm','loot_undead_ruins','itm_trinket_story_charm',5);

-- BEAST DEN
INSERT OR IGNORE INTO loot_table_entries
(id,loot_table_id,item_def_id,weight,min_qty,max_qty)
VALUES
('lte_beast_leather','loot_beast_den','itm_leather',25,1,4),
('lte_beast_herb','loot_beast_den','itm_healing_herb',20,1,3);

-- ANCIENT RUINS
INSERT OR IGNORE INTO loot_table_entries
(id,loot_table_id,tag_id,weight,rarity_bias)
VALUES
('lte_ruins_trinket','loot_ancient_ruins','item:trinket',30,1),
('lte_ruins_weapon','loot_ancient_ruins','item:weapon',15,1);

/* =========================================================
   4.4 AI AGGREGATED STAT VIEWS
   ========================================================= */

-- What an item provides in human-readable form
CREATE VIEW IF NOT EXISTS v_item_stats AS
SELECT
  id AS item_def_id,
  name,
  type,
  slot,
  rarity,
  base_value,
  json_extract(meta_json,'$.damage') AS damage,
  json_extract(meta_json,'$.armor') AS armor,
  json_extract(meta_json,'$.speed') AS speed,
  json_extract(meta_json,'$.luck') AS luck,
  json_extract(meta_json,'$.light') AS light
FROM item_defs;

-- Character equipped stats summary (AI GOLD)
CREATE VIEW IF NOT EXISTS v_character_equipment_stats AS
SELECT
  c.id AS character_id,
  SUM(COALESCE(json_extract(d.meta_json,'$.damage'),0)) AS total_damage,
  SUM(COALESCE(json_extract(d.meta_json,'$.armor'),0)) AS total_armor,
  SUM(COALESCE(json_extract(d.meta_json,'$.speed'),0)) AS total_speed,
  SUM(COALESCE(json_extract(d.meta_json,'$.luck'),0)) AS total_luck
FROM characters c
LEFT JOIN equipment e ON e.character_id = c.id
LEFT JOIN item_instances i ON i.id = e.item_instance_id
LEFT JOIN item_defs d ON d.id = i.item_def_id
GROUP BY c.id;

/* =========================================================
   4.5 ECONOMY & PRICE CONTEXT (AI + WORLD AWARE)
   ========================================================= */

-- Settlement pricing modifiers
CREATE TABLE IF NOT EXISTS settlement_price_mods (
  settlement_id TEXT PRIMARY KEY,
  price_mult REAL NOT NULL DEFAULT 1.0,
  rarity_bias INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE
);

INSERT OR IGNORE INTO settlement_price_mods (settlement_id,price_mult,rarity_bias) VALUES
('set_brindlewick',1.0,0),
('set_emberhold',1.1,1),
('set_cinderport',0.95,1);

-- AI-readable price breakdown
CREATE VIEW IF NOT EXISTS v_shop_effective_prices AS
SELECT
  s.id AS shop_id,
  i.id AS item_def_id,
  i.name,
  i.base_value,
  s.sell_mult,
  COALESCE(sp.price_mult,1.0) AS settlement_mult,
  ROUND(i.base_value * s.sell_mult * COALESCE(sp.price_mult,1.0)) AS final_price
FROM shops s
JOIN settlements_v2 setl ON setl.id = s.settlement_id
LEFT JOIN settlement_price_mods sp ON sp.settlement_id = setl.id
JOIN item_defs i;

COMMIT;
