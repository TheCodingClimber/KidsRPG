PRAGMA foreign_keys = ON;

-- =========================================================
-- 026_seed_hearthlands_settlements_and_pois.sql
-- Seeds Hearthlands settlements (from hearthlands_v1.json)
-- and POIs into DB so DB is canonical for gameplay entities.
-- =========================================================

-- ---------- Settlements ----------
-- Table expected: settlements_v2(id, region_id, name, type, x, y, tier, prosperity, meta_json, ...)
-- If you haven't created settlements_v2 yet, add 025_create_settlements_v2.sql first.

INSERT OR IGNORE INTO settlements_v2
(id, region_id, name, type, x, y, tier, prosperity, meta_json)
VALUES
('cinderport_city',       'hearthlands', 'Cinderport (City)',        'town',    92, 12, 4, 68, '{"signpost":{"x":92,"y":12},"travelFee":40}'),
('brindlewick_town',      'hearthlands', 'Brindlewick (Town)',       'town',    20, 18, 3, 55, '{"signpost":{"x":20,"y":18},"travelFee":25}'),
('stoneford_town',        'hearthlands', 'Stoneford (Town)',         'town',    48, 56, 3, 54, '{"signpost":{"x":48,"y":56},"travelFee":28}'),
('pinehollow_town',       'hearthlands', 'Pinehollow (Town)',        'town',    12, 38, 3, 52, '{"signpost":{"x":12,"y":38},"travelFee":26}'),

('willowmere_village',    'hearthlands', 'Willowmere (Village)',     'village', 16, 14, 2, 46, '{"signpost":{"x":16,"y":14},"travelFee":12}'),
('goldenfield_village',   'hearthlands', 'Goldenfield (Village)',    'village', 30, 20, 2, 48, '{"signpost":{"x":30,"y":20},"travelFee":12}'),
('ravenwatch_village',    'hearthlands', 'Ravenwatch (Village)',     'village', 74, 10, 2, 45, '{"signpost":{"x":74,"y":10},"travelFee":14}'),
('mistvale_village',      'hearthlands', 'Mistvale (Village)',       'village', 62, 46, 2, 44, '{"signpost":{"x":62,"y":46},"travelFee":14}'),
('emberbrook_village',    'hearthlands', 'Emberbrook (Village)',     'village', 88, 62, 2, 43, '{"signpost":{"x":88,"y":62},"travelFee":15}');

-- =========================================================
-- POIs
-- =========================================================
-- You likely already have a POI table in your migrations.
-- I won't guess the name and break your build.
--
-- So: create a new canonical POI table that matches your JSON if needed.

CREATE TABLE IF NOT EXISTS pois_v1 (
  id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,           -- ruins, cave, enemy_camp, etc.
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  min_level INTEGER NOT NULL DEFAULT 1,
  note TEXT NOT NULL DEFAULT '',
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_pois_v1_region ON pois_v1(region_id);
CREATE INDEX IF NOT EXISTS idx_pois_v1_type ON pois_v1(type);

INSERT OR IGNORE INTO pois_v1
(id, region_id, name, type, x, y, min_level, note, meta_json)
VALUES
('ruins_high_barrows',        'hearthlands', 'High Barrows Ruins',          'ruins',        24,  8,  3, '', '{}'),
('ruins_sunken_watch',        'hearthlands', 'Sunken Watch',                'ruins',        14, 54,  4, '', '{}'),

('cave_whisper_hole',         'hearthlands', 'Whisper Hole',                'cave',         10,  4,  2, '', '{}'),
('cave_stone_throat',         'hearthlands', 'Stone Throat Cavern',         'cave',         68, 28,  5, '', '{}'),

('camp_bandits_northroad',    'hearthlands', 'Bandit Camp: Northroad',      'enemy_camp',   44, 22,  2, '', '{"threat":"bandits"}'),
('camp_raiders_southlake',    'hearthlands', 'Raider Camp: Southlake',      'enemy_camp',   58, 48,  4, '', '{"threat":"raiders"}'),

('mountain_dragon_summit',    'hearthlands', 'Dragon Summit',               'mountain_summit', 95, 59, 12, 'High-level only. Dragon taming lives here.', '{"boss":"dragon"}');
