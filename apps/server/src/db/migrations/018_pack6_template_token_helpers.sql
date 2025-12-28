PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6.6 — TEMPLATE TOKEN HELPERS (NO HARDCODED LISTS)
   Purpose:
     - DB-driven token pools for templates:
       {item} {creature} {giver_role} {mystery} {poi_type} {faction} etc.
     - Generator flow:
       1) pick a notice_post_template row
       2) pick lists for each token via template_token_bindings
       3) pull random token values via SQL with filters (danger/biome/etc)
       4) substitute tokens in app layer
   ========================================================= */

/* ---------------------------------------------------------
   6.6.A) Token lists (named pools)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS template_token_lists (
  id TEXT PRIMARY KEY,                 -- ttl_items_common
  name TEXT NOT NULL,                  -- "Items — Common"
  token TEXT NOT NULL,                 -- item/creature/mystery/giver_role etc
  description TEXT NOT NULL DEFAULT '',
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_ttl_token ON template_token_lists(token);


/* ---------------------------------------------------------
   6.6.B) Token values (members of a list, with filters)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS template_token_values (
  id TEXT PRIMARY KEY,                 -- ttv_xxx
  list_id TEXT NOT NULL,               -- ttl_items_common
  value TEXT NOT NULL,                 -- what gets substituted into {token}
  weight INTEGER NOT NULL DEFAULT 10,  -- weighted randomness

  -- Optional filters:
  category TEXT NULL,                  -- help/trade/bounty/mystery/etc (notice category)
  tone TEXT NULL,                      -- gentle/neutral/firm
  region_id TEXT NULL,
  settlement_id TEXT NULL,
  biome TEXT NULL,                     -- forest/swamp/mountain/coast/plains/urban/cave/ruins
  min_danger INTEGER NOT NULL DEFAULT 0,
  max_danger INTEGER NOT NULL DEFAULT 100,

  tags_json TEXT NOT NULL DEFAULT '[]',-- JSON array of strings for AI reasoning
  meta_json TEXT NOT NULL DEFAULT '{}',

  FOREIGN KEY (list_id) REFERENCES template_token_lists(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ttv_list ON template_token_values(list_id);
CREATE INDEX IF NOT EXISTS idx_ttv_filters
ON template_token_values(list_id, category, tone, biome, min_danger, max_danger);


/* ---------------------------------------------------------
   6.6.C) Token bindings (which lists a template can use)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS template_token_bindings (
  id TEXT PRIMARY KEY,                  -- ttb_help_item_default
  token TEXT NOT NULL,                  -- item/creature/mystery/etc
  list_id TEXT NOT NULL,                -- ttl_items_common

  notice_category TEXT NULL,            -- if set, applies only to that category
  notice_tone TEXT NULL,                -- if set, applies only to that tone

  min_danger INTEGER NOT NULL DEFAULT 0,
  max_danger INTEGER NOT NULL DEFAULT 100,
  biome TEXT NULL,
  region_id TEXT NULL,
  settlement_id TEXT NULL,

  priority INTEGER NOT NULL DEFAULT 10, -- higher wins when multiple match
  meta_json TEXT NOT NULL DEFAULT '{}',

  FOREIGN KEY (list_id) REFERENCES template_token_lists(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ttb_match
ON template_token_bindings(token, notice_category, notice_tone, biome, region_id, settlement_id, priority);


/* ---------------------------------------------------------
   6.6.D) Helpful VIEW: bindings with list info
   --------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_token_bindings AS
SELECT
  b.id AS binding_id,
  b.token,
  b.list_id,
  l.name AS list_name,
  b.notice_category,
  b.notice_tone,
  b.min_danger,
  b.max_danger,
  b.biome,
  b.region_id,
  b.settlement_id,
  b.priority,
  b.meta_json
FROM template_token_bindings b
JOIN template_token_lists l ON l.id = b.list_id;


/* ---------------------------------------------------------
   Optional VIEW: values joined with token name
   --------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_token_values AS
SELECT
  v.id,
  v.list_id,
  l.token,
  v.value,
  v.weight,
  v.category,
  v.tone,
  v.region_id,
  v.settlement_id,
  v.biome,
  v.min_danger,
  v.max_danger,
  v.tags_json,
  v.meta_json
FROM template_token_values v
JOIN template_token_lists l ON l.id = v.list_id;


/* =========================================================
   SEED: LISTS
   ========================================================= */
INSERT OR IGNORE INTO template_token_lists (id, name, token, description, meta_json) VALUES
-- ITEMS
('ttl_items_common',        'Items — Common',         'item',       'Everyday goods and materials.', '{"kidFriendly":true}'),
('ttl_items_food',          'Items — Food',           'item',       'Food items and snacks.',        '{"kidFriendly":true}'),
('ttl_items_materials',     'Items — Materials',      'item',       'Crafting materials.',           '{"kidFriendly":true}'),
('ttl_items_tools',         'Items — Tools',          'item',       'Tools, kits, and utility.',     '{"kidFriendly":true}'),

-- CREATURES
('ttl_creatures_low',       'Creatures — Low Danger', 'creature',   'Low danger creatures.',         '{"kidFriendly":true}'),
('ttl_creatures_mid',       'Creatures — Mid Danger', 'creature',   'Mid danger creatures.',         '{"kidFriendly":true}'),
('ttl_creatures_high',      'Creatures — High Danger','creature',   'Higher danger creatures.',      '{"kidFriendly":true}'),

-- MYSTERY LINES
('ttl_mystery_gentle',      'Mystery Lines — Gentle', 'mystery',    'Soft, curious hooks.',          '{"kidFriendly":true}'),
('ttl_mystery_neutral',     'Mystery Lines — Neutral','mystery',    'Neutral investigation hooks.',  '{"kidFriendly":true}'),
('ttl_mystery_firm',        'Mystery Lines — Firm',   'mystery',    'Urgent, still kid-safe.',       '{"kidFriendly":true}'),

-- GIVER ROLE (hint; generator chooses an NPC by role)
('ttl_giver_roles',         'Giver Roles',            'giver_role', 'NPC role hints.',               '{"kidFriendly":true}'),

-- FACTION NAMES (literal token option; can also pull from factions table)
('ttl_faction_names',       'Faction Names',          'faction',    'Faction names or labels.',      '{"kidFriendly":true}'),

-- POI TYPES (literal token option; can also pull from pois table)
('ttl_poi_types',           'POI Types',              'poi_type',   'POI type hints.',               '{"kidFriendly":true}');


/* =========================================================
   SEED: TOKEN VALUES — ITEMS
   ========================================================= */
INSERT OR IGNORE INTO template_token_values
(id, list_id, value, weight, category, tone, region_id, settlement_id, biome, min_danger, max_danger, tags_json, meta_json)
VALUES
-- Common
('ttv_item_rope',      'ttl_items_common',    'a coil of rope',        12, NULL, NULL, NULL, NULL, NULL, 0,100, '["utility"]', '{}'),
('ttv_item_torch',     'ttl_items_common',    'a torch',               14, NULL, NULL, NULL, NULL, NULL, 0,100, '["light"]',   '{}'),
('ttv_item_bandage',   'ttl_items_common',    'clean bandages',        12, NULL, NULL, NULL, NULL, NULL, 0,100, '["healing"]', '{}'),
('ttv_item_blanket',   'ttl_items_common',    'a warm blanket',        10, NULL, NULL, NULL, NULL, NULL, 0,100, '["comfort"]', '{}'),
('ttv_item_soap',      'ttl_items_common',    'a bar of soap',          8, NULL, NULL, NULL, NULL, NULL, 0,100, '["cleanup"]', '{}'),
('ttv_item_candle',    'ttl_items_common',    'a candle',              10, NULL, NULL, NULL, NULL, NULL, 0,100, '["light"]',   '{}'),
('ttv_item_waterskin', 'ttl_items_common',    'a waterskin',           10, NULL, NULL, NULL, NULL, NULL, 0,100, '["travel"]',  '{}'),
('ttv_item_chalk',     'ttl_items_common',    'a stick of chalk',       8, NULL, NULL, NULL, NULL, NULL, 0,100, '["marking"]', '{}'),
('ttv_item_map_paper', 'ttl_items_common',    'map paper',              8, 'explore', NULL, NULL, NULL, NULL, 0,100, '["mapping"]','{}'),
('ttv_item_nails',     'ttl_items_common',    'a handful of nails',     9, 'repair',  NULL, NULL, NULL, NULL, 0,100, '["repair"]','{}'),

-- Food
('ttv_food_bread',     'ttl_items_food',      'fresh bread',           14, 'trade', NULL, NULL, NULL, NULL, 0,100, '["food"]', '{}'),
('ttv_food_jerky',     'ttl_items_food',      'jerky',                 12, 'trade', NULL, NULL, NULL, NULL, 0,100, '["food"]', '{}'),
('ttv_food_apples',    'ttl_items_food',      'a sack of apples',      10, 'trade', NULL, NULL, NULL, NULL, 0,100, '["food"]', '{}'),
('ttv_food_honey',     'ttl_items_food',      'a jar of honey',         8, 'trade', NULL, NULL, NULL, NULL, 0,100, '["food"]', '{}'),
('ttv_food_cheese',    'ttl_items_food',      'a wheel of cheese',      8, 'trade', NULL, NULL, NULL, NULL, 0,100, '["food"]', '{}'),

-- Materials
('ttv_mat_wood',       'ttl_items_materials', 'a bundle of wood',       14, 'crafting', NULL, NULL, NULL, NULL, 0,100, '["material:wood"]', '{}'),
('ttv_mat_iron_ore',   'ttl_items_materials', 'iron ore',               12, 'crafting', NULL, NULL, NULL, NULL, 0,100, '["material:iron"]', '{}'),
('ttv_mat_leather',    'ttl_items_materials', 'leather strips',         10, 'crafting', NULL, NULL, NULL, NULL, 0,100, '["material:leather"]', '{}'),
('ttv_mat_cloth',      'ttl_items_materials', 'cloth scraps',           10, 'crafting', NULL, NULL, NULL, NULL, 0,100, '["material:cloth"]', '{}'),
('ttv_mat_herbs',      'ttl_items_materials', 'healing herbs',          12, 'trade',    NULL, NULL, NULL, NULL, 0,100, '["herb"]', '{}'),

-- Tools / Kits
('ttv_tool_repairkit_small','ttl_items_tools','a small repair kit',     12, 'repair', NULL, NULL, NULL, NULL, 0, 80, '["repair_kit"]', '{"suggestItemDef":"itm_repair_kit_small"}'),
('ttv_tool_repairkit_big',  'ttl_items_tools','a sturdy repair kit',     8, 'repair', NULL, NULL, NULL, NULL,30,100, '["repair_kit"]', '{"suggestItemDef":"itm_repair_kit_large"}'),
('ttv_tool_hammer',         'ttl_items_tools','a light hammer',         10, 'repair', NULL, NULL, NULL, NULL, 0,100, '["tool"]', '{}'),
('ttv_tool_needles',        'ttl_items_tools','sewing needles',          9, 'crafting',NULL, NULL, NULL, NULL, 0,100, '["tool","cloth"]', '{}'),
('ttv_tool_tongs',          'ttl_items_tools','smithing tongs',          7, 'crafting',NULL, NULL, NULL, NULL,10,100, '["tool","forge"]', '{}');


/* =========================================================
   SEED: TOKEN VALUES — CREATURES (danger-banded)
   ========================================================= */
INSERT OR IGNORE INTO template_token_values
(id, list_id, value, weight, category, tone, region_id, settlement_id, biome, min_danger, max_danger, tags_json, meta_json)
VALUES
-- Low
('ttv_creature_rats',     'ttl_creatures_low',  'rats',                 14, 'bounty', NULL, NULL, NULL, 'urban',  0, 35, '["small"]', '{}'),
('ttv_creature_boars',    'ttl_creatures_low',  'wild boars',           10, 'bounty', NULL, NULL, NULL, 'forest', 5, 45, '["beast"]', '{}'),
('ttv_creature_wolves',   'ttl_creatures_low',  'wolves',               10, 'bounty', NULL, NULL, NULL, 'forest',10, 55, '["beast"]', '{}'),
('ttv_creature_snakes',   'ttl_creatures_low',  'snakes',                9, 'bounty', NULL, NULL, NULL, 'swamp',  0, 50, '["beast"]', '{}'),
('ttv_creature_sprites',  'ttl_creatures_low',  'mischief sprites',      6, 'mystery',NULL, NULL, NULL, 'forest', 0, 40, '["mythic","nonlethal"]', '{"kidFriendly":true}'),

-- Mid
('ttv_creature_goblins',  'ttl_creatures_mid',  'goblin pranksters',    12, 'bounty', NULL, NULL, NULL, 'hills', 20, 75, '["humanoid"]', '{"kidFriendly":true}'),
('ttv_creature_bandits',  'ttl_creatures_mid',  'road troublemakers',   12, 'bounty', NULL, NULL, NULL, 'plains',25, 85, '["humanoid"]', '{"kidFriendly":true}'),
('ttv_creature_bears',    'ttl_creatures_mid',  'a grumpy bear',         8, 'bounty', NULL, NULL, NULL, 'forest',25, 80, '["beast"]', '{}'),
('ttv_creature_spiders',  'ttl_creatures_mid',  'big cave spiders',      8, 'bounty', NULL, NULL, NULL, 'cave',  30, 85, '["beast"]', '{}'),

-- High (still kid-safe wording)
('ttv_creature_ogre',     'ttl_creatures_high', 'an ogre',               8, 'bounty', NULL, NULL, NULL, 'hills', 55,100, '["humanoid","big"]', '{"kidFriendly":true}'),
('ttv_creature_warg',     'ttl_creatures_high', 'a warg',                7, 'bounty', NULL, NULL, NULL, 'forest',60,100, '["beast","big"]', '{}'),
('ttv_creature_masks',    'ttl_creatures_high', 'masked troublemakers',  6, 'bounty', NULL, NULL, NULL, 'ruins', 60,100, '["humanoid","mystery"]', '{"kidFriendly":true}'),
('ttv_creature_troll',    'ttl_creatures_high', 'a troll',               6, 'bounty', NULL, NULL, NULL, 'swamp', 65,100, '["big"]', '{}');


/* =========================================================
   SEED: TOKEN VALUES — MYSTERY LINES (NO MUTATION)
   ========================================================= */
INSERT OR IGNORE INTO template_token_values
(id, list_id, value, weight, category, tone, region_id, settlement_id, biome, min_danger, max_danger, tags_json, meta_json)
VALUES
-- Gentle
('ttv_mys_gentle_1','ttl_mystery_gentle','someone heard a lullaby-like humming at dusk', 12,'mystery','gentle',NULL,NULL,NULL,0,100,'["soft_hook"]','{}'),
('ttv_mys_gentle_2','ttl_mystery_gentle','a lantern-light floated where no one was standing',10,'mystery','gentle',NULL,NULL,NULL,0,100,'["soft_hook"]','{}'),
('ttv_mys_gentle_3','ttl_mystery_gentle','tiny footprints appeared and then simply stopped', 10,'mystery','gentle',NULL,NULL,NULL,0,100,'["soft_hook"]','{}'),
('ttv_mys_gentle_4','ttl_mystery_gentle','a note was found that says: “Meet me by the old stone.”',9,'mystery','gentle',NULL,NULL,NULL,0,100,'["note"]','{}'),
('ttv_mys_gentle_5','ttl_mystery_gentle','someone swears the wind whispered a name near {poi}',8,'mystery','gentle',NULL,NULL,NULL,0,100,'["spooky_but_safe"]','{}'),

-- Neutral
('ttv_mys_neu_1','ttl_mystery_neutral','a tool went missing with no footprints nearby', 12,'mystery','neutral',NULL,NULL,NULL,0,100,'["investigation"]','{}'),
('ttv_mys_neu_2','ttl_mystery_neutral','a trail marker was moved overnight',            10,'mystery','neutral',NULL,NULL,NULL,0,100,'["roads"]','{}'),
('ttv_mys_neu_3','ttl_mystery_neutral','a faint glow was seen near {poi} after midnight',10,'mystery','neutral',NULL,NULL,NULL,0,100,'["glow"]','{}'),
('ttv_mys_neu_4','ttl_mystery_neutral','someone found an old key with no matching lock', 9,'mystery','neutral',NULL,NULL,NULL,0,100,'["item_hook"]','{}'),
('ttv_mys_neu_5','ttl_mystery_neutral','a traveler keeps asking: “Where is the singing stone?”',8,'mystery','neutral',NULL,NULL,NULL,0,100,'["traveler_hook"]','{}'),

-- Firm (kid-safe, just urgent)
('ttv_mys_firm_1','ttl_mystery_firm','don’t go alone—something is changing near {poi}',10,'mystery','firm',NULL,NULL,NULL,0,100,'["urgent"]','{}'),
('ttv_mys_firm_2','ttl_mystery_firm','lights out tonight: stay near lanterns unless helping the watch',10,'mystery','firm',NULL,NULL,NULL,0,100,'["safety"]','{}'),
('ttv_mys_firm_3','ttl_mystery_firm','supplies vanished—return them and nobody gets in trouble',9,'mystery','firm',NULL,NULL,NULL,0,100,'["stern_but_safe"]','{}'),
('ttv_mys_firm_4','ttl_mystery_firm','the road is closed until someone checks the hazard near {poi}',8,'mystery','firm',NULL,NULL,NULL,0,100,'["roads","safety"]','{}');


/* =========================================================
   SEED: GIVER ROLE HINTS
   ========================================================= */
INSERT OR IGNORE INTO template_token_values
(id, list_id, value, weight, category, tone, region_id, settlement_id, biome, min_danger, max_danger, tags_json, meta_json)
VALUES
('ttv_giver_guard',     'ttl_giver_roles','guard',      12, NULL, NULL, NULL,NULL,NULL,0,100,'["role"]','{}'),
('ttv_giver_warden',    'ttl_giver_roles','warden',     10, NULL, NULL, NULL,NULL,NULL,0,100,'["role"]','{}'),
('ttv_giver_merchant',  'ttl_giver_roles','merchant',   12, NULL, NULL, NULL,NULL,NULL,0,100,'["role"]','{}'),
('ttv_giver_blacksmith','ttl_giver_roles','blacksmith', 10, NULL, NULL, NULL,NULL,NULL,0,100,'["role"]','{}'),
('ttv_giver_alchemist', 'ttl_giver_roles','alchemist',   9, NULL, NULL, NULL,NULL,NULL,0,100,'["role"]','{}'),
('ttv_giver_innkeeper', 'ttl_giver_roles','innkeeper',   9, NULL, NULL, NULL,NULL,NULL,0,100,'["role"]','{}'),
('ttv_giver_child',     'ttl_giver_roles','child',       7, 'fun','gentle',NULL,NULL,NULL,0, 40,'["role","kids"]','{}'),
('ttv_giver_healer',    'ttl_giver_roles','healer',      8, 'help',NULL,   NULL,NULL,NULL,0, 80,'["role"]','{}'),
('ttv_giver_tinkerer',  'ttl_giver_roles','tinkerer',    7, 'crafting',NULL,NULL,NULL,NULL,0, 90,'["role"]','{}'),
('ttv_giver_farmer',    'ttl_giver_roles','farmer',      7, 'help',NULL,   NULL,NULL,NULL,0, 70,'["role"]','{}');


/* =========================================================
   SEED: FACTION & POI TYPE TOKENS
   ========================================================= */
INSERT OR IGNORE INTO template_token_values
(id, list_id, value, weight, category, tone, region_id, settlement_id, biome, min_danger, max_danger, tags_json, meta_json)
VALUES
('ttv_fac_wardens',   'ttl_faction_names','Hearth Wardens',  10, NULL,NULL,NULL,NULL,NULL,0,100,'["faction"]','{}'),
('ttv_fac_merchants', 'ttl_faction_names','Merchants Guild', 10, NULL,NULL,NULL,NULL,NULL,0,100,'["faction"]','{}'),
('ttv_fac_iron_oath', 'ttl_faction_names','Iron Oath',        9, NULL,NULL,NULL,NULL,NULL,0,100,'["faction"]','{}'),

('ttv_poi_ruins',     'ttl_poi_types','ruins',  10, NULL,NULL,NULL,NULL,NULL,0,100,'["poi_type"]','{}'),
('ttv_poi_cave',      'ttl_poi_types','cave',   10, NULL,NULL,NULL,NULL,NULL,0,100,'["poi_type"]','{}'),
('ttv_poi_camp',      'ttl_poi_types','camp',   10, NULL,NULL,NULL,NULL,NULL,0,100,'["poi_type"]','{}'),
('ttv_poi_shrine',    'ttl_poi_types','shrine',  7, NULL,NULL,NULL,NULL,NULL,0,100,'["poi_type"]','{}');


/* =========================================================
   BINDINGS: map notice category/tone -> token lists
   ========================================================= */
INSERT OR IGNORE INTO template_token_bindings
(id, token, list_id, notice_category, notice_tone, min_danger, max_danger, biome, region_id, settlement_id, priority, meta_json)
VALUES
-- {item}
('ttb_item_default',       'item',      'ttl_items_common',    NULL,      NULL,     0,100, NULL, NULL, NULL, 10, '{}'),
('ttb_item_trade_food',    'item',      'ttl_items_food',      'trade',   NULL,     0,100, NULL, NULL, NULL, 30, '{}'),
('ttb_item_crafting_mat',  'item',      'ttl_items_materials', 'crafting',NULL,     0,100, NULL, NULL, NULL, 30, '{}'),
('ttb_item_repair_tools',  'item',      'ttl_items_tools',     'repair',  NULL,     0,100, NULL, NULL, NULL, 35, '{}'),

-- {creature}
('ttb_creature_low',       'creature',  'ttl_creatures_low',   'bounty',  NULL,     0,45,  NULL, NULL, NULL, 20, '{}'),
('ttb_creature_mid',       'creature',  'ttl_creatures_mid',   'bounty',  NULL,    35,80,  NULL, NULL, NULL, 25, '{}'),
('ttb_creature_high',      'creature',  'ttl_creatures_high',  'bounty',  NULL,    70,100, NULL, NULL, NULL, 30, '{}'),

-- {mystery}
('ttb_mystery_gentle',     'mystery',   'ttl_mystery_gentle',  'mystery', 'gentle', 0,100, NULL, NULL, NULL, 30, '{}'),
('ttb_mystery_neutral',    'mystery',   'ttl_mystery_neutral', 'mystery', 'neutral',0,100, NULL, NULL, NULL, 30, '{}'),
('ttb_mystery_firm',       'mystery',   'ttl_mystery_firm',    'mystery', 'firm',   0,100, NULL, NULL, NULL, 30, '{}'),

-- {giver_role}
('ttb_giver_roles_default','giver_role','ttl_giver_roles',     NULL,      NULL,     0,100, NULL, NULL, NULL, 10, '{}'),

-- {faction}
('ttb_faction_default',    'faction',   'ttl_faction_names',   NULL,      NULL,     0,100, NULL, NULL, NULL, 10, '{}'),

-- {poi_type}
('ttb_poi_type_default',   'poi_type',  'ttl_poi_types',       NULL,      NULL,     0,100, NULL, NULL, NULL, 10, '{}');


COMMIT;
