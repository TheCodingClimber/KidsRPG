PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 4: Economy + Repairs + Loot Tables + Trinkets (Extensive)
   Runs AFTER 002_world_alive.sql
   ========================================================= */


/* =========================================================
   4.1) Tag-based shop stock rules (scales forever)
   ========================================================= */

CREATE TABLE IF NOT EXISTS shop_stock_tag_rules (
  shop_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  min_qty INTEGER NOT NULL DEFAULT 0,
  max_qty INTEGER NOT NULL DEFAULT 5,
  weight INTEGER NOT NULL DEFAULT 10,
  price_mult REAL NOT NULL DEFAULT 1.0,
  PRIMARY KEY (shop_id, tag_id),
  FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_shop_stock_tag_rules_shop ON shop_stock_tag_rules(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_stock_tag_rules_tag ON shop_stock_tag_rules(tag_id);


/* =========================================================
   4.2) Loot tables (items OR tags as entries)
   ========================================================= */

CREATE TABLE IF NOT EXISTS loot_tables (
  id TEXT PRIMARY KEY,               -- loot_bandits_t1
  name TEXT NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}' -- {"theme":"bandits","tier":1}
);

-- Entries can reference either an item_def_id OR a tag_id.
CREATE TABLE IF NOT EXISTS loot_table_entries (
  loot_table_id TEXT NOT NULL,
  item_def_id TEXT NULL,
  tag_id TEXT NULL,
  weight INTEGER NOT NULL DEFAULT 10,
  min_qty INTEGER NOT NULL DEFAULT 1,
  max_qty INTEGER NOT NULL DEFAULT 1,
  rarity_min TEXT NULL,              -- optional: "common"
  rarity_max TEXT NULL,              -- optional: "rare"
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE,
  CHECK (
    (item_def_id IS NOT NULL AND tag_id IS NULL) OR
    (item_def_id IS NULL AND tag_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_loot_entries_table ON loot_table_entries(loot_table_id);
CREATE INDEX IF NOT EXISTS idx_loot_entries_item ON loot_table_entries(item_def_id);
CREATE INDEX IF NOT EXISTS idx_loot_entries_tag ON loot_table_entries(tag_id);

-- Map POI "theme" -> default loot table(s)
CREATE TABLE IF NOT EXISTS loot_theme_map (
  theme TEXT PRIMARY KEY,            -- "bandits","beasts","undead","ruins","mountain","forest"
  loot_table_id TEXT NOT NULL,
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE
);

-- Optional per-POI override
CREATE TABLE IF NOT EXISTS poi_loot_overrides (
  poi_id TEXT PRIMARY KEY,
  loot_table_id TEXT NOT NULL,
  FOREIGN KEY (poi_id) REFERENCES pois(id) ON DELETE CASCADE,
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE
);


/* =========================================================
   4.3) Seed tags (materials, categories, trinket types, loot groups)
   ========================================================= */

INSERT OR IGNORE INTO tags (id, label) VALUES
-- Materials
('material:cloth', 'Cloth'),
('material:stone', 'Stone'),
('material:glass', 'Glass'),
('material:bone', 'Bone'),
('material:herb', 'Herb'),
('material:gem', 'Gem'),
('material:silver', 'Silver'),

-- Item categories
('item:tool', 'Tool'),
('item:trinket', 'Trinket'),
('item:component', 'Component'),
('item:ammo', 'Ammo'),
('item:healing', 'Healing'),
('item:utility', 'Utility'),

-- Herb families (AI-friendly)
('herb:common', 'Common Herbs'),
('herb:forest', 'Forest Herbs'),
('herb:swamp', 'Swamp Herbs'),
('herb:mountain', 'Mountain Herbs'),
('herb:rare', 'Rare Herbs'),

-- Loot groups (for tables + shop stocking)
('loot:bandit', 'Bandit Loot'),
('loot:beast', 'Beast Loot'),
('loot:undead', 'Undead Loot'),
('loot:ruins', 'Ruins Loot'),
('loot:treasure', 'Treasure Loot'),

-- Repair
('repair:kit', 'Repair Kits'),
('repair:metal', 'Metal Repairs'),
('repair:leather', 'Leather Repairs'),
('repair:wood', 'Wood Repairs'),

-- Weapon subtypes (optional but nice for AI)
('weapon:blade', 'Bladed Weapons'),
('weapon:blunt', 'Blunt Weapons'),
('weapon:polearm', 'Polearms'),
('weapon:ranged', 'Ranged Weapons'),

-- Armor slots as tags (optional)
('armor:helmet', 'Helmet'),
('armor:torso', 'Torso'),
('armor:offhand', 'Offhand'),
('armor:feet', 'Feet'),
('armor:back', 'Back'),

-- Trinket types (kid-safe magic flavor)
('trinket:charm', 'Charm'),
('trinket:ring', 'Ring'),
('trinket:amulet', 'Amulet'),
('trinket:totem', 'Totem'),
('trinket:coin', 'Lucky Coin'),
('trinket:relic', 'Relic'),
('trinket:toy', 'Mystic Toy');


/* =========================================================
   4.4) Add missing baseline items referenced by recipes (meat, cloth)
   ========================================================= */

INSERT OR IGNORE INTO item_defs
(id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json)
VALUES
('itm_meat',  'Meat',  'consumable', NULL, 'common', 1, 10, 2, 0.3, 0, '{"stamina":1,"tags":["item:food"]}'),
('itm_cloth', 'Cloth', 'resource',   NULL, 'common', 1, 50, 1, 0.2, 0, '{"tags":["item:resource","material:cloth"]}'),
('itm_stone', 'Stone', 'resource',   NULL, 'common', 1, 50, 1, 0.7, 0, '{"tags":["item:resource","material:stone"]}'),
('itm_bone',  'Bone',  'resource',   NULL, 'common', 1, 50, 2, 0.4, 0, '{"tags":["item:resource","material:bone"]}');

INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_cloth','material:cloth'),
('itm_stone','material:stone'),
('itm_bone','material:bone'),
('itm_meat','item:food');


/* =========================================================
   4.5) Components + ammo + repair items (AI-friendly meta_json)
   ========================================================= */

INSERT OR IGNORE INTO item_defs
(id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json)
VALUES
-- Components
('itm_iron_ingot',     'Iron Ingot',     'resource',  NULL, 'common',   1, 50, 5, 0.9, 0, '{"tags":["item:resource","item:component","material:iron"]}'),
('itm_wood_plank',     'Wood Plank',     'resource',  NULL, 'common',   1, 50, 2, 0.6, 0, '{"tags":["item:resource","item:component","material:wood"]}'),
('itm_leather_strap',  'Leather Strap',  'resource',  NULL, 'common',   1, 50, 2, 0.2, 0, '{"tags":["item:resource","item:component","material:leather"]}'),
('itm_cloth_roll',     'Cloth Roll',     'resource',  NULL, 'common',   1, 25, 3, 0.5, 0, '{"tags":["item:resource","item:component","material:cloth"]}'),
('itm_simple_handle',  'Simple Handle',  'resource',  NULL, 'common',   1, 25, 2, 0.4, 0, '{"tags":["item:resource","item:component","material:wood"]}'),
('itm_bowstring',      'Bowstring',      'resource',  NULL, 'common',   1, 25, 3, 0.1, 0, '{"tags":["item:resource","item:component","material:cloth"]}'),
('itm_glass_vial',     'Glass Vial',     'resource',  NULL, 'common',   1, 25, 4, 0.2, 0, '{"tags":["item:resource","item:component","material:glass","station:alchemy"]}'),
('itm_wax',            'Wax',            'resource',  NULL, 'common',   1, 25, 2, 0.2, 0, '{"tags":["item:resource","item:component"]}'),
('itm_thread_spool',   'Thread Spool',   'resource',  NULL, 'common',   1, 25, 2, 0.1, 0, '{"tags":["item:resource","item:component","material:cloth"]}'),

-- Ammo (generous stacks so kids don’t suffer)
('itm_arrow',          'Arrows',         'ammo',      NULL, 'common',   1, 30, 1, 0.02, 0, '{"ammoFor":["weapon:ranged"],"tags":["item:ammo"]}'),
('itm_bolt',           'Bolts',          'ammo',      NULL, 'common',   1, 30, 1, 0.03, 0, '{"ammoFor":["weapon:ranged"],"tags":["item:ammo"]}'),
('itm_sling_stone',    'Sling Stones',   'ammo',      NULL, 'common',   1, 50, 1, 0.02, 0, '{"ammoFor":["weapon:ranged"],"tags":["item:ammo","material:stone"]}'),

-- Repair / maintenance
('itm_repair_kit_basic','Basic Repair Kit','tool',    NULL, 'common',   1, 10, 12, 0.7, 0,
 '{"tags":["item:tool","repair:kit","repair:wood","repair:leather"],"repairs":{"tags":["material:wood","material:leather"],"amount":20}}'),
('itm_repair_kit_metal','Metal Repair Kit','tool',    NULL, 'uncommon', 1, 10, 20, 0.9, 0,
 '{"tags":["item:tool","repair:kit","repair:metal"],"repairs":{"tags":["material:iron"],"amount":25}}'),
('itm_whetstone',      'Whetstone',      'tool',      NULL, 'common',   1, 10, 8,  0.3, 0,
 '{"tags":["item:tool"],"maintain":{"weapon":1,"note":"sharpens"}}'),
('itm_armor_oil',      'Armor Oil',      'consumable',NULL, 'uncommon', 1, 10, 10, 0.3, 0,
 '{"tags":["item:utility"],"buff":{"durabilityLossMult":0.8,"turns":10}}'),

-- Utility / travel
('itm_chalk',          'Chalk',          'tool',      NULL, 'common',   1, 20, 1,  0.05,0, '{"tags":["item:tool","item:utility"],"mark":1}'),
('itm_flint',          'Flint & Steel',  'tool',      NULL, 'common',   0, 1,  6,  0.2, 50,'{"tags":["item:tool","station:campfire"],"ignite":1}'),
('itm_map_scroll',     'Map Scroll',     'tool',      NULL, 'uncommon', 0, 1,  18, 0.1, 0,'{"tags":["item:utility"],"revealFog":1}');

-- Tag links for components/repair/ammo
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_iron_ingot','item:component'),
('itm_wood_plank','item:component'),
('itm_leather_strap','item:component'),
('itm_cloth_roll','item:component'),
('itm_glass_vial','item:component'),
('itm_arrow','item:ammo'),
('itm_bolt','item:ammo'),
('itm_sling_stone','item:ammo'),
('itm_repair_kit_basic','repair:kit'),
('itm_repair_kit_metal','repair:kit'),
('itm_map_scroll','item:utility'),
('itm_chalk','item:utility');


/* =========================================================
   4.6) Apothecary herb expansion (many, kid-safe)
   ========================================================= */

INSERT OR IGNORE INTO item_defs
(id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json)
VALUES
-- Common herbs
('itm_herb_mintleaf',     'Mintleaf',     'resource', NULL, 'common',   1, 50, 2, 0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:common"],"effects":{"calm":1}}'),
('itm_herb_sunpetal',     'Sunpetal',     'resource', NULL, 'common',   1, 50, 3, 0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:common"],"effects":{"heal":1}}'),
('itm_herb_bitterroot',   'Bitterroot',   'resource', NULL, 'common',   1, 50, 2, 0.06, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:common"],"effects":{"antidote":1}}'),
('itm_herb_greenthread',  'Greenthread',  'resource', NULL, 'common',   1, 50, 2, 0.04, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:common"],"effects":{"stamina":1}}'),

-- Forest herbs
('itm_herb_moonmoss',     'Moonmoss',     'resource', NULL, 'uncommon', 1, 50, 5, 0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:forest"],"effects":{"night_vision":1}}'),
('itm_herb_foxglove',     'Foxglove',     'resource', NULL, 'uncommon', 1, 50, 5, 0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:forest"],"effects":{"regen":1}}'),
('itm_herb_sapflower',    'Sapflower',    'resource', NULL, 'uncommon', 1, 50, 4, 0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:forest"],"effects":{"shield":1}}'),

-- Swamp herbs
('itm_herb_swampreed',    'Swampreed',    'resource', NULL, 'uncommon', 1, 50, 4, 0.06, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:swamp"],"effects":{"antidote":2}}'),
('itm_herb_ghostcap',     'Ghostcap',     'resource', NULL, 'rare',     1, 25, 8, 0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:swamp"],"effects":{"invisibility_hint":1}}'),
('itm_herb_murkthistle',  'Murkthistle',  'resource', NULL, 'uncommon', 1, 50, 4, 0.06, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:swamp"],"effects":{"slow_resist":1}}'),

-- Mountain herbs
('itm_herb_peakpepper',   'Peakpepper',   'resource', NULL, 'uncommon', 1, 50, 5, 0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:mountain"],"effects":{"warmth":1}}'),
('itm_herb_stonesage',    'Stonesage',    'resource', NULL, 'rare',     1, 25, 9, 0.06, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:mountain"],"effects":{"armor":1}}'),

-- Rare herbs
('itm_herb_starlily',     'Starlily',     'resource', NULL, 'rare',     1, 25, 12,0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:rare"],"effects":{"heal":3}}'),
('itm_herb_emberbloom',   'Emberbloom',   'resource', NULL, 'rare',     1, 25, 12,0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:rare"],"effects":{"fire_resist":1}}'),
('itm_herb_frostfern',    'Frostfern',    'resource', NULL, 'rare',     1, 25, 12,0.05, 0, '{"tags":["item:resource","material:herb","station:alchemy","herb:rare"],"effects":{"cold_resist":1}}');

INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_herb_mintleaf','material:herb'),
('itm_herb_sunpetal','material:herb'),
('itm_herb_bitterroot','material:herb'),
('itm_herb_greenthread','material:herb'),
('itm_herb_moonmoss','material:herb'),
('itm_herb_foxglove','material:herb'),
('itm_herb_sapflower','material:herb'),
('itm_herb_swampreed','material:herb'),
('itm_herb_ghostcap','material:herb'),
('itm_herb_murkthistle','material:herb'),
('itm_herb_peakpepper','material:herb'),
('itm_herb_stonesage','material:herb'),
('itm_herb_starlily','material:herb'),
('itm_herb_emberbloom','material:herb'),
('itm_herb_frostfern','material:herb'),
('itm_herb_mintleaf','herb:common'),
('itm_herb_sunpetal','herb:common'),
('itm_herb_bitterroot','herb:common'),
('itm_herb_greenthread','herb:common'),
('itm_herb_moonmoss','herb:forest'),
('itm_herb_foxglove','herb:forest'),
('itm_herb_sapflower','herb:forest'),
('itm_herb_swampreed','herb:swamp'),
('itm_herb_ghostcap','herb:swamp'),
('itm_herb_murkthistle','herb:swamp'),
('itm_herb_peakpepper','herb:mountain'),
('itm_herb_stonesage','herb:mountain'),
('itm_herb_starlily','herb:rare'),
('itm_herb_emberbloom','herb:rare'),
('itm_herb_frostfern','herb:rare');


/* =========================================================
   4.7) Trinkets (BIG list, kid-safe, flavorful, AI-readable)
   type=trinket, slot=NULL, meta_json includes passive hints/tags
   ========================================================= */

INSERT OR IGNORE INTO item_defs
(id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json)
VALUES
-- Common trinkets (fun, small perks)
('itm_trinket_lucky_coin',      'Lucky Coin',         'trinket', NULL, 'common',   0,1, 8, 0.05,0, '{"tags":["item:trinket","trinket:coin"],"perk":{"luck":1}}'),
('itm_trinket_bell_of_bravery', 'Bell of Bravery',    'trinket', NULL, 'common',   0,1, 10,0.10,0, '{"tags":["item:trinket","trinket:charm"],"perk":{"brave":1}}'),
('itm_trinket_feather_charm',   'Feather Charm',      'trinket', NULL, 'common',   0,1, 10,0.05,0, '{"tags":["item:trinket","trinket:charm"],"perk":{"speed":1}}'),
('itm_trinket_glow_pebble',     'Glow Pebble',        'trinket', NULL, 'common',   0,1, 10,0.10,0, '{"tags":["item:trinket","trinket:toy"],"light":1}'),
('itm_trinket_story_pin',       'Story Pin',          'trinket', NULL, 'common',   0,1, 10,0.05,0, '{"tags":["item:trinket","trinket:charm"],"perk":{"charm":1}}'),
('itm_trinket_scout_badge',     'Scout Badge',        'trinket', NULL, 'common',   0,1, 10,0.05,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"mapSense":1}}'),
('itm_trinket_river_stone',     'Smooth River Stone', 'trinket', NULL, 'common',   0,1, 6, 0.10,0, '{"tags":["item:trinket","trinket:toy"],"perk":{"calm":1}}'),
('itm_trinket_tiny_hourglass',  'Tiny Hourglass',     'trinket', NULL, 'common',   0,1, 12,0.10,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"focus":1}}'),

-- Uncommon trinkets (clear identity)
('itm_trinket_warding_knot',    'Warding Knot',       'trinket', NULL, 'uncommon', 0,1, 20,0.10,0, '{"tags":["item:trinket","trinket:totem"],"resist":{"fear":1}}'),
('itm_trinket_moon_amulet',     'Moon Amulet',        'trinket', NULL, 'uncommon', 0,1, 22,0.10,0, '{"tags":["item:trinket","trinket:amulet"],"perk":{"nightVision":1}}'),
('itm_trinket_sun_medallion',   'Sun Medallion',      'trinket', NULL, 'uncommon', 0,1, 22,0.10,0, '{"tags":["item:trinket","trinket:amulet"],"perk":{"warmth":1}}'),
('itm_trinket_whisper_shell',   'Whisper Shell',      'trinket', NULL, 'uncommon', 0,1, 24,0.10,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"hearing":1}}'),
('itm_trinket_brass_compass',   'Brass Compass',      'trinket', NULL, 'uncommon', 0,1, 26,0.20,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"navigation":1}}'),
('itm_trinket_gleam_ring',      'Gleam Ring',         'trinket', NULL, 'uncommon', 0,1, 28,0.05,0, '{"tags":["item:trinket","trinket:ring"],"light":1}'),
('itm_trinket_bardic_pick',     'Bardic Pick',        'trinket', NULL, 'uncommon', 0,1, 20,0.05,0, '{"tags":["item:trinket","trinket:toy"],"perk":{"music":1}}'),
('itm_trinket_courage_ribbon',  'Courage Ribbon',     'trinket', NULL, 'uncommon', 0,1, 20,0.05,0, '{"tags":["item:trinket","trinket:charm"],"perk":{"brave":2}}'),

-- Rare trinkets (bigger fantasy)
('itm_trinket_ember_locket',    'Ember Locket',       'trinket', NULL, 'rare',     0,1, 55,0.10,0, '{"tags":["item:trinket","trinket:amulet"],"resist":{"fire":1},"perk":{"brave":1}}'),
('itm_trinket_frost_charm',     'Frost Charm',        'trinket', NULL, 'rare',     0,1, 55,0.10,0, '{"tags":["item:trinket","trinket:charm"],"resist":{"cold":1},"perk":{"calm":1}}'),
('itm_trinket_thunder_bead',    'Thunder Bead',       'trinket', NULL, 'rare',     0,1, 60,0.05,0, '{"tags":["item:trinket","trinket:totem"],"perk":{"spark":1}}'),
('itm_trinket_leaf_crown',      'Leaf Crown',         'trinket', NULL, 'rare',     0,1, 60,0.10,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"natureFriend":1}}'),
('itm_trinket_star_map',        'Star Map',           'trinket', NULL, 'rare',     0,1, 65,0.10,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"discover":1}}'),
('itm_trinket_silent_brooch',   'Silent Brooch',      'trinket', NULL, 'rare',     0,1, 65,0.05,0, '{"tags":["item:trinket","trinket:charm"],"perk":{"sneak":1}}'),
('itm_trinket_guardian_eye',    'Guardian Eye',       'trinket', NULL, 'rare',     0,1, 70,0.10,0, '{"tags":["item:trinket","trinket:amulet"],"perk":{"dangerSense":1}}'),
('itm_trinket_friendship_band', 'Friendship Band',    'trinket', NULL, 'rare',     0,1, 60,0.05,0, '{"tags":["item:trinket","trinket:ring"],"perk":{"teamwork":1}}'),

-- Epic trinkets (wow moments, still kid-safe)
('itm_trinket_phoenix_feather', 'Phoenix Feather',    'trinket', NULL, 'epic',     0,1, 120,0.05,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"reviveHint":1},"resist":{"fire":2}}'),
('itm_trinket_dragon_scale',    'Dragon Scale',       'trinket', NULL, 'epic',     0,1, 140,0.20,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"brave":2},"resist":{"fear":2}}'),
('itm_trinket_ancient_sigils',  'Ancient Sigils',     'trinket', NULL, 'epic',     0,1, 150,0.10,0, '{"tags":["item:trinket","trinket:relic"],"perk":{"lore":2,"puzzleSense":1}}');

INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_trinket_lucky_coin','item:trinket'),
('itm_trinket_bell_of_bravery','item:trinket'),
('itm_trinket_feather_charm','item:trinket'),
('itm_trinket_glow_pebble','item:trinket'),
('itm_trinket_story_pin','item:trinket'),
('itm_trinket_scout_badge','item:trinket'),
('itm_trinket_river_stone','item:trinket'),
('itm_trinket_tiny_hourglass','item:trinket'),
('itm_trinket_warding_knot','item:trinket'),
('itm_trinket_moon_amulet','item:trinket'),
('itm_trinket_sun_medallion','item:trinket'),
('itm_trinket_whisper_shell','item:trinket'),
('itm_trinket_brass_compass','item:trinket'),
('itm_trinket_gleam_ring','item:trinket'),
('itm_trinket_bardic_pick','item:trinket'),
('itm_trinket_courage_ribbon','item:trinket'),
('itm_trinket_ember_locket','item:trinket'),
('itm_trinket_frost_charm','item:trinket'),
('itm_trinket_thunder_bead','item:trinket'),
('itm_trinket_leaf_crown','item:trinket'),
('itm_trinket_star_map','item:trinket'),
('itm_trinket_silent_brooch','item:trinket'),
('itm_trinket_guardian_eye','item:trinket'),
('itm_trinket_friendship_band','item:trinket'),
('itm_trinket_phoenix_feather','item:trinket'),
('itm_trinket_dragon_scale','item:trinket'),
('itm_trinket_ancient_sigils','item:trinket'),
('itm_trinket_lucky_coin','trinket:coin'),
('itm_trinket_gleam_ring','trinket:ring'),
('itm_trinket_friendship_band','trinket:ring'),
('itm_trinket_moon_amulet','trinket:amulet'),
('itm_trinket_sun_medallion','trinket:amulet'),
('itm_trinket_ember_locket','trinket:amulet'),
('itm_trinket_guardian_eye','trinket:amulet'),
('itm_trinket_warding_knot','trinket:totem'),
('itm_trinket_thunder_bead','trinket:totem'),
('itm_trinket_glow_pebble','trinket:toy'),
('itm_trinket_bardic_pick','trinket:toy'),
('itm_trinket_star_map','trinket:relic'),
('itm_trinket_ancient_sigils','trinket:relic'),
('itm_trinket_dragon_scale','trinket:relic');


/* =========================================================
   4.8) Crafting recipes for components, ammo, and repairs
   ========================================================= */

-- NOTE: uses your existing recipes + recipe_ingredients tables from 002.

INSERT OR IGNORE INTO recipes (id, name, output_item_def_id, output_qty, station, difficulty, meta_json) VALUES
-- Components
('rcp_iron_ingot',    'Smelt Iron Ingot',   'itm_iron_ingot',    1, 'forge',     2, '{"timeSec":25}'),
('rcp_wood_plank',    'Cut Wood Planks',    'itm_wood_plank',    2, 'workbench', 1, '{"timeSec":15}'),
('rcp_leather_strap', 'Make Leather Straps','itm_leather_strap', 2, 'workbench', 1, '{"timeSec":15}'),
('rcp_cloth_roll',    'Roll Cloth',         'itm_cloth_roll',    1, 'workbench', 1, '{"timeSec":15}'),
('rcp_simple_handle', 'Carve Handle',       'itm_simple_handle', 1, 'workbench', 1, '{"timeSec":15}'),
('rcp_bowstring',     'Twist Bowstring',    'itm_bowstring',     1, 'workbench', 2, '{"timeSec":20}'),
('rcp_glass_vial',    'Blow Glass Vial',    'itm_glass_vial',    1, 'forge',     3, '{"timeSec":30}'),

-- Ammo
('rcp_arrows',        'Craft Arrows',       'itm_arrow',        10, 'workbench', 2, '{"timeSec":25}'),
('rcp_bolts',         'Craft Bolts',        'itm_bolt',         10, 'workbench', 2, '{"timeSec":25}'),
('rcp_sling_stones',  'Smooth Sling Stones','itm_sling_stone',  20, 'workbench', 1, '{"timeSec":15}'),

-- Repairs / maintenance (simple)
('rcp_repair_kit_basic', 'Assemble Basic Repair Kit','itm_repair_kit_basic', 1, 'workbench', 2, '{"timeSec":25}'),
('rcp_repair_kit_metal', 'Assemble Metal Repair Kit','itm_repair_kit_metal', 1, 'forge',     3, '{"timeSec":30}'),
('rcp_whetstone',        'Shape Whetstone',         'itm_whetstone',         1, 'workbench',  1, '{"timeSec":15}'),
('rcp_armor_oil',        'Mix Armor Oil',           'itm_armor_oil',         1, 'alchemy',    2, '{"timeSec":20}');

INSERT OR IGNORE INTO recipe_ingredients (recipe_id, item_def_id, qty) VALUES
-- Components
('rcp_iron_ingot', 'itm_iron_ore',  3),
('rcp_wood_plank', 'itm_wood',      2),
('rcp_leather_strap','itm_leather', 1),
('rcp_cloth_roll', 'itm_cloth',     6),
('rcp_simple_handle','itm_wood',    2),
('rcp_bowstring',  'itm_thread_spool', 1),
('rcp_bowstring',  'itm_cloth',     2),
('rcp_glass_vial', 'itm_stone',     1),   -- pretend sand/glass source
('rcp_glass_vial', 'itm_wood',      1),   -- fuel/heat

-- Ammo
('rcp_arrows', 'itm_wood',      2),
('rcp_arrows', 'itm_iron_ore',  1),
('rcp_bolts',  'itm_wood',      2),
('rcp_bolts',  'itm_iron_ore',  1),
('rcp_sling_stones','itm_stone', 2),

-- Repairs
('rcp_repair_kit_basic', 'itm_cloth', 2),
('rcp_repair_kit_basic', 'itm_leather', 1),
('rcp_repair_kit_basic', 'itm_wax', 1),
('rcp_repair_kit_metal', 'itm_iron_ingot', 1),
('rcp_repair_kit_metal', 'itm_cloth', 1),
('rcp_repair_kit_metal', 'itm_wax', 1),
('rcp_whetstone', 'itm_stone', 2),
('rcp_armor_oil', 'itm_herb_mintleaf', 1),
('rcp_armor_oil', 'itm_glass_vial', 1);


/* =========================================================
   4.9) Tag-based shop stocking seeds (scalable defaults)
   ========================================================= */

-- General store: food, basic tools, basic resources, ammo
INSERT OR IGNORE INTO shop_stock_tag_rules (shop_id, tag_id, min_qty, max_qty, weight, price_mult) VALUES
('shop_brindlewick_general','item:food',      6, 16, 40, 1.00),
('shop_brindlewick_general','item:tool',      2,  6, 20, 1.05),
('shop_brindlewick_general','item:resource',  6, 20, 20, 1.00),
('shop_brindlewick_general','item:ammo',      8, 20, 18, 1.00),
('shop_brindlewick_general','item:utility',   1,  4, 10, 1.10);

-- Blacksmith: weapons/armor + components + repairs
INSERT OR IGNORE INTO shop_stock_tag_rules (shop_id, tag_id, min_qty, max_qty, weight, price_mult) VALUES
('shop_brindlewick_smith','item:weapon',     1, 4, 28, 1.10),
('shop_brindlewick_smith','item:armor',      1, 4, 22, 1.10),
('shop_brindlewick_smith','item:component',  3,10, 18, 1.05),
('shop_brindlewick_smith','repair:kit',      1, 4, 14, 1.10);

-- Alchemist: herbs/components/potions
INSERT OR IGNORE INTO shop_stock_tag_rules (shop_id, tag_id, min_qty, max_qty, weight, price_mult) VALUES
('shop_emberhold_alchemy','material:herb',   6, 18, 40, 1.00),
('shop_emberhold_alchemy','item:component',  2,  8, 10, 1.05),
('shop_emberhold_alchemy','item:healing',    1,  6, 18, 1.10),
('shop_emberhold_alchemy','item:utility',    1,  4, 10, 1.10);

-- Make sure core potions/bandages get a healing tag for stocking
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_small_potion','item:healing'),
('itm_bandage','item:healing');


/* =========================================================
   4.10) Loot table seeds (EXTENSIVE)
   Strategy: entries mix specific items + tag pools for variety.
   ========================================================= */

INSERT OR IGNORE INTO loot_tables (id, name, meta_json) VALUES
-- Bandits
('loot_bandits_t1','Bandit Cache (Tier 1)','{"theme":"bandits","tier":1}'),
('loot_bandits_t2','Bandit Cache (Tier 2)','{"theme":"bandits","tier":2}'),

-- Beasts / caves
('loot_beasts_t1','Beast Den (Tier 1)','{"theme":"beasts","tier":1}'),
('loot_beasts_t2','Beast Den (Tier 2)','{"theme":"beasts","tier":2}'),

-- Undead / ruins
('loot_undead_t1','Cursed Bones (Tier 1)','{"theme":"undead","tier":1}'),
('loot_undead_t2','Cursed Bones (Tier 2)','{"theme":"undead","tier":2}'),
('loot_ruins_t1','Ancient Ruins (Tier 1)','{"theme":"ruins","tier":1}'),
('loot_ruins_t2','Ancient Ruins (Tier 2)','{"theme":"ruins","tier":2}'),

-- Nature / forest
('loot_forest_t1','Forest Finds (Tier 1)','{"theme":"forest","tier":1}'),
('loot_forest_t2','Forest Finds (Tier 2)','{"theme":"forest","tier":2}'),

-- Mountain / summit
('loot_mountain_t2','Mountain Hoard (Tier 2)','{"theme":"mountain","tier":2}'),
('loot_mountain_t3','Summit Hoard (Tier 3)','{"theme":"mountain","tier":3}'),

-- Treasure-focused (trinkets!)
('loot_treasure_t1','Treasure Pouch (Tier 1)','{"theme":"treasure","tier":1}'),
('loot_treasure_t2','Treasure Pouch (Tier 2)','{"theme":"treasure","tier":2}');

-- Theme mapping (your POIs already use themes like "undead","beasts")
INSERT OR IGNORE INTO loot_theme_map (theme, loot_table_id) VALUES
('bandits','loot_bandits_t1'),
('beasts','loot_beasts_t1'),
('undead','loot_undead_t1'),
('ruins','loot_ruins_t1'),
('forest','loot_forest_t1'),
('mountain','loot_mountain_t2'),
('treasure','loot_treasure_t1');

-- BANDIT T1: food, ammo, simple tools, small chance of gear
INSERT OR IGNORE INTO loot_table_entries
(loot_table_id, item_def_id, tag_id, weight, min_qty, max_qty, rarity_min, rarity_max, meta_json) VALUES
('loot_bandits_t1','itm_bread',NULL,  30,1,3,NULL,NULL,'{}'),
('loot_bandits_t1','itm_jerky',NULL,  30,1,3,NULL,NULL,'{}'),
('loot_bandits_t1','itm_meat',NULL,   18,1,2,NULL,NULL,'{}'),
('loot_bandits_t1','itm_torch',NULL,  18,1,2,NULL,NULL,'{}'),
('loot_bandits_t1','itm_rope',NULL,   12,1,1,NULL,NULL,'{}'),
('loot_bandits_t1','itm_chalk',NULL,  10,1,2,NULL,NULL,'{}'),
('loot_bandits_t1','itm_lockpick',NULL,6,1,2,NULL,NULL,'{}'),
('loot_bandits_t1',NULL,'item:ammo',  24,5,20,NULL,NULL,'{}'),
('loot_bandits_t1',NULL,'item:trinket',10,1,1,'common','uncommon','{"note":"small charm"}'),
('loot_bandits_t1',NULL,'item:weapon', 8,1,1,'common','uncommon','{"note":"light weapon"}'),
('loot_bandits_t1',NULL,'item:armor',  6,1,1,'common','uncommon','{"note":"light armor"}'),
('loot_bandits_t1','itm_repair_kit_basic',NULL,6,1,1,NULL,NULL,'{}');

-- BANDIT T2: better tools, repair kits, more trinkets, occasional rare
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_bandits_t2','itm_map_scroll',NULL,10,1,1,NULL,NULL,'{}'),
('loot_bandits_t2','itm_lockpick',NULL,12,1,3,NULL,NULL,'{}'),
('loot_bandits_t2','itm_repair_kit_basic',NULL,10,1,2,NULL,NULL,'{}'),
('loot_bandits_t2','itm_repair_kit_metal',NULL,6,1,1,NULL,NULL,'{}'),
('loot_bandits_t2',NULL,'item:ammo',24,10,30,NULL,NULL,'{}'),
('loot_bandits_t2',NULL,'item:trinket',18,1,1,'common','rare','{"note":"bandit keepsake"}'),
('loot_bandits_t2',NULL,'item:weapon',12,1,1,'uncommon','rare','{"note":"stolen weapon"}'),
('loot_bandits_t2',NULL,'item:armor',10,1,1,'uncommon','rare','{"note":"stolen armor"}'),
('loot_bandits_t2','itm_small_potion',NULL,10,1,2,NULL,NULL,'{}');

-- BEAST T1: hides, bones, food, herbs, small trinket chance
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_beasts_t1','itm_leather',NULL,30,1,4,NULL,NULL,'{}'),
('loot_beasts_t1','itm_bone',NULL,20,1,3,NULL,NULL,'{}'),
('loot_beasts_t1','itm_meat',NULL,28,1,3,NULL,NULL,'{}'),
('loot_beasts_t1',NULL,'material:herb',16,1,3,'common','uncommon','{"note":"foraged"}'),
('loot_beasts_t1','itm_bandage',NULL,10,1,2,NULL,NULL,'{}'),
('loot_beasts_t1',NULL,'item:trinket',8,1,1,'common','uncommon','{"note":"odd find in den"}');

-- BEAST T2: more herbs, chance at rare herb, better trinkets
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_beasts_t2','itm_leather',NULL,30,2,6,NULL,NULL,'{}'),
('loot_beasts_t2','itm_bone',NULL,22,2,5,NULL,NULL,'{}'),
('loot_beasts_t2','itm_meat',NULL,24,2,5,NULL,NULL,'{}'),
('loot_beasts_t2',NULL,'material:herb',22,2,6,'common','rare','{"note":"foraged pile"}'),
('loot_beasts_t2','itm_small_potion',NULL,10,1,2,NULL,NULL,'{}'),
('loot_beasts_t2',NULL,'item:trinket',14,1,1,'uncommon','rare','{"note":"beast-touched charm"}');

-- UNDEAD T1: bones, torches, bandages, low trinkets
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_undead_t1','itm_bone',NULL,30,2,6,NULL,NULL,'{}'),
('loot_undead_t1','itm_torch',NULL,18,1,3,NULL,NULL,'{}'),
('loot_undead_t1','itm_bandage',NULL,18,1,3,NULL,NULL,'{}'),
('loot_undead_t1','itm_small_potion',NULL,10,1,1,NULL,NULL,'{}'),
('loot_undead_t1',NULL,'item:trinket',10,1,1,'common','rare','{"note":"old locket or charm"}'),
('loot_undead_t1',NULL,'item:weapon',6,1,1,'common','uncommon','{"note":"rusty but usable"}');

-- UNDEAD T2: more trinkets, rare chance, some gear
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_undead_t2','itm_bone',NULL,28,3,8,NULL,NULL,'{}'),
('loot_undead_t2','itm_torch',NULL,16,1,3,NULL,NULL,'{}'),
('loot_undead_t2','itm_small_potion',NULL,14,1,2,NULL,NULL,'{}'),
('loot_undead_t2',NULL,'item:trinket',22,1,1,'uncommon','epic','{"note":"relic"}'),
('loot_undead_t2',NULL,'item:armor',12,1,1,'uncommon','rare','{"note":"grave-guard piece"}'),
('loot_undead_t2',NULL,'item:weapon',12,1,1,'uncommon','rare','{"note":"grave-guard weapon"}');

-- RUINS T1: components, trinkets, utility
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_ruins_t1','itm_iron_ingot',NULL,10,1,2,NULL,NULL,'{}'),
('loot_ruins_t1','itm_glass_vial',NULL,10,1,2,NULL,NULL,'{}'),
('loot_ruins_t1','itm_map_scroll',NULL,6,1,1,NULL,NULL,'{}'),
('loot_ruins_t1','itm_chalk',NULL,10,1,3,NULL,NULL,'{}'),
('loot_ruins_t1',NULL,'item:trinket',22,1,1,'common','rare','{"note":"ancient curiosity"}'),
('loot_ruins_t1',NULL,'item:component',18,1,4,'common','uncommon','{"note":"salvaged parts"}'),
('loot_ruins_t1',NULL,'material:herb',10,1,2,'common','uncommon','{"note":"odd dried herb"}');

-- RUINS T2: more trinkets, better components, rare herbs
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_ruins_t2','itm_iron_ingot',NULL,14,1,3,NULL,NULL,'{}'),
('loot_ruins_t2','itm_glass_vial',NULL,12,1,3,NULL,NULL,'{}'),
('loot_ruins_t2','itm_repair_kit_metal',NULL,8,1,1,NULL,NULL,'{}'),
('loot_ruins_t2',NULL,'item:trinket',30,1,1,'uncommon','epic','{"note":"ancient relic"}'),
('loot_ruins_t2',NULL,'item:component',20,2,6,'common','rare','{"note":"salvaged stash"}'),
('loot_ruins_t2',NULL,'material:herb',12,1,3,'uncommon','rare','{"note":"rare herb"}');

-- FOREST T1: wood/leather, herbs, small trinkets
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_forest_t1','itm_wood',NULL,28,2,8,NULL,NULL,'{}'),
('loot_forest_t1','itm_leather',NULL,14,1,4,NULL,NULL,'{}'),
('loot_forest_t1',NULL,'material:herb',24,1,4,'common','uncommon','{"note":"forage"}'),
('loot_forest_t1','itm_herb_mintleaf',NULL,10,1,2,NULL,NULL,'{}'),
('loot_forest_t1','itm_herb_sunpetal',NULL,10,1,2,NULL,NULL,'{}'),
('loot_forest_t1',NULL,'item:trinket',8,1,1,'common','uncommon','{"note":"forest charm"}');

-- FOREST T2: better herbs, more trinkets
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_forest_t2','itm_wood',NULL,26,4,12,NULL,NULL,'{}'),
('loot_forest_t2','itm_leather',NULL,16,2,6,NULL,NULL,'{}'),
('loot_forest_t2',NULL,'material:herb',28,2,6,'common','rare','{"note":"deep woods forage"}'),
('loot_forest_t2',NULL,'item:trinket',14,1,1,'uncommon','rare','{"note":"nature relic"}'),
('loot_forest_t2','itm_small_potion',NULL,8,1,1,NULL,NULL,'{}');

-- MOUNTAIN T2: stone, iron, cold herbs, trinkets
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_mountain_t2','itm_stone',NULL,26,3,10,NULL,NULL,'{}'),
('loot_mountain_t2','itm_iron_ore',NULL,18,2,6,NULL,NULL,'{}'),
('loot_mountain_t2','itm_herb_peakpepper',NULL,14,1,3,NULL,NULL,'{}'),
('loot_mountain_t2','itm_herb_frostfern',NULL,10,1,2,NULL,NULL,'{}'),
('loot_mountain_t2',NULL,'item:trinket',16,1,1,'uncommon','rare','{"note":"mountain charm"}'),
('loot_mountain_t2','itm_repair_kit_metal',NULL,8,1,1,NULL,NULL,'{}');

-- MOUNTAIN T3: summit hoard – big trinket chances + epic
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_mountain_t3','itm_iron_ingot',NULL,16,2,5,NULL,NULL,'{}'),
('loot_mountain_t3','itm_herb_starlily',NULL,10,1,2,NULL,NULL,'{}'),
('loot_mountain_t3','itm_herb_stonesage',NULL,10,1,2,NULL,NULL,'{}'),
('loot_mountain_t3',NULL,'item:trinket',34,1,1,'rare','epic','{"note":"summit relic"}'),
('loot_mountain_t3',NULL,'item:armor',12,1,1,'rare','epic','{"note":"guardian gear"}'),
('loot_mountain_t3',NULL,'item:weapon',12,1,1,'rare','epic','{"note":"guardian weapon"}');

-- TREASURE T1/T2: mostly trinkets + utility + a little healing
INSERT OR IGNORE INTO loot_table_entries VALUES
('loot_treasure_t1',NULL,'item:trinket',40,1,1,'common','rare','{"note":"shiny"}'),
('loot_treasure_t1','itm_small_potion',NULL,10,1,1,NULL,NULL,'{}'),
('loot_treasure_t1','itm_map_scroll',NULL,6,1,1,NULL,NULL,'{}'),
('loot_treasure_t1','itm_lockpick',NULL,8,1,2,NULL,NULL,'{}'),

('loot_treasure_t2',NULL,'item:trinket',52,1,1,'uncommon','epic','{"note":"great prize"}'),
('loot_treasure_t2','itm_small_potion',NULL,12,1,2,NULL,NULL,'{}'),
('loot_treasure_t2','itm_map_scroll',NULL,10,1,1,NULL,NULL,'{}'),
('loot_treasure_t2','itm_repair_kit_metal',NULL,8,1,1,NULL,NULL,'{}');


/* =========================================================
   4.11) Optional: POI override example (uncomment to use)
   =========================================================
   Example:
   - make Ashen Summit use the big summit hoard.
   ========================================================= */

-- INSERT OR IGNORE INTO poi_loot_overrides (poi_id, loot_table_id) VALUES
-- ('poi_ashen_summit','loot_mountain_t3');


COMMIT;
