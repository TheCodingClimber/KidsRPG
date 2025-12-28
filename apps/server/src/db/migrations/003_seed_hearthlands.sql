BEGIN;
PRAGMA defer_foreign_keys = ON;
PRAGMA foreign_keys = OFF;

-- =========================================================
-- 003_seed_hearthlands.sql (MATCHES CURRENT SCHEMA)
-- Targets:
--   regions
--   settlements_v2 (with safety + meta_json; tier optional)
--   pois (NOT pois_v1)
--   named_regions_v1
-- =========================================================

/* =========================================================
   Region registry
   ========================================================= */

INSERT OR IGNORE INTO regions (id, name, width, height, meta_json)
VALUES ('hearthlands', 'The Hearthlands', 160, 100, '{"seed":"003_seed_hearthlands"}');


/* =========================================================
   Settlements
   NOTE: settlements_v2 schema includes:
     prosperity, safety, banner_color, sigil_id, faction_id, meta_json
   tier exists now (from 002_world_entities safe extension), so we include it.
   ========================================================= */

INSERT OR REPLACE INTO settlements_v2
(id, region_id, name, type, x, y, tier, prosperity, safety, banner_color, sigil_id, faction_id, meta_json)
VALUES
('cinderport_city','hearthlands','Cinderport (City)','town',92,12,3,55,55,'royal_blue','crown',NULL,'{"signpost":{"x":92,"y":12},"travelFee":40}'),
('brindlewick_town','hearthlands','Brindlewick (Town)','town',20,18,3,55,55,'emerald','shield',NULL,'{"signpost":{"x":20,"y":18},"travelFee":25}'),
('stoneford_town','hearthlands','Stoneford (Town)','town',48,56,3,55,55,'midnight','shield',NULL,'{"signpost":{"x":48,"y":56},"travelFee":28}'),
('pinehollow_town','hearthlands','Pinehollow (Town)','town',12,38,3,55,55,'emerald','wolf',NULL,'{"signpost":{"x":12,"y":38},"travelFee":26}'),

('willowmere_village','hearthlands','Willowmere (Village)','village',16,14,2,45,50,'teal','moon',NULL,'{"signpost":{"x":16,"y":14},"travelFee":12}'),
('goldenfield_village','hearthlands','Goldenfield (Village)','village',30,20,2,45,50,'copper','oak',NULL,'{"signpost":{"x":30,"y":20},"travelFee":12}'),
('ravenwatch_village','hearthlands','Ravenwatch (Village)','village',74,10,2,45,48,'crimson','shield',NULL,'{"signpost":{"x":74,"y":10},"travelFee":14}'),
('mistvale_village','hearthlands','Mistvale (Village)','village',62,46,2,45,48,'teal','moon',NULL,'{"signpost":{"x":62,"y":46},"travelFee":14}'),
('emberbrook_village','hearthlands','Emberbrook (Village)','village',88,62,2,45,48,'scarlet','hammer',NULL,'{"signpost":{"x":88,"y":62},"travelFee":15}'),

('camp_sunreed_ferry','hearthlands','Sunreed Ferry Camp','camp',18,77,1,30,40,'emerald','star',NULL,'{"signpost":{"x":18,"y":77},"travelFee":8}'),
('hamlet_mirewatch','hearthlands','Mirewatch Hamlet','hamlet',44,61,1,35,42,'ice','moon',NULL,'{"signpost":{"x":44,"y":61},"travelFee":10}'),
('camp_boulderhook','hearthlands','Boulderhook Outpost','outpost',62,80,1,32,40,'copper','hammer',NULL,'{"signpost":{"x":62,"y":80},"travelFee":9}'),
('hamlet_lakeshade','hearthlands','Lakeshade Hamlet','hamlet',26,87,1,35,42,'teal','oak',NULL,'{"signpost":{"x":26,"y":87},"travelFee":10}');


/* =========================================================
   POIs
   IMPORTANT: Your schema uses `pois` table (not pois_v1)
   pois columns: id, region_id, name, type, x, y, danger, recommended_level, icon, meta_json
   ========================================================= */

INSERT OR REPLACE INTO pois
(id, region_id, name, type, x, y, danger, recommended_level, icon, meta_json)
VALUES
('ruins_high_barrows','hearthlands','High Barrows Ruins','ruins',24,8,40,3,'🏚️','{}'),
('ruins_sunken_watch','hearthlands','Sunken Watch','ruins',14,54,55,4,'🏚️','{}'),
('cave_whisper_hole','hearthlands','Whisper Hole','cave',10,4,30,2,'🕳️','{}'),
('cave_stone_throat','hearthlands','Stone Throat Cavern','cave',68,28,65,5,'🕳️','{}'),
('camp_bandits_northroad','hearthlands','Bandit Camp: Northroad','camp',44,22,35,2,'⛺','{}'),
('camp_raiders_southlake','hearthlands','Raider Camp: Southlake','camp',58,48,55,4,'⛺','{}'),
('mountain_dragon_summit','hearthlands','Dragon Summit','summit',95,59,95,12,'⛰️','{"note":"High-level only. Dragon taming lives here."}'),
('ruins_drowned_chapel','hearthlands','Drowned Chapel','ruins',34,79,55,4,'🏚️','{"note":"A half-submerged chapel. Bells ring when no wind blows."}'),
('shrine_moonlit_spring','hearthlands','Moonlit Spring','shrine',52,85,35,3,'🛕','{"note":"A clear spring that glows faintly at night. Good omens… mostly."}'),
('cave_bloodroot_grotto','hearthlands','Bloodroot Grotto','cave',24,62,65,5,'🕳️','{"note":"A cave with red-stained roots and echoing whispers."}'),
('camp_smugglers_cut','hearthlands','Smugglers'' Cut','camp',65,84,55,4,'⛺','{"note":"Hidden caches and a rough plank bridge across reeds."}');


/* =========================================================
   Named regions (rectangles)
   ========================================================= */

DELETE FROM named_regions_v1 WHERE region_id = 'hearthlands';

INSERT INTO named_regions_v1 (region_id, name, x1, y1, x2, y2, meta_json)
VALUES
('hearthlands','Whisperwood',6,1,16,5,'{}'),
('hearthlands','Lake Oath',10,9,30,16,'{}'),
('hearthlands','High Barrows',18,5,34,10,'{}'),
('hearthlands','Cartroad Spine',24,17,70,55,'{}'),
('hearthlands','Emberhold Basin',34,22,50,34,'{}'),
('hearthlands','Southlake Expanse',20,40,78,49,'{}'),
('hearthlands','Cinder Coast',80,8,99,20,'{}'),
('hearthlands','Dragonridge',86,54,99,69,'{}'),
('hearthlands','Sunreed Marsh',14,70,60,88,'{}'),
('hearthlands','Siltmere Lake',18,74,62,90,'{}'),
('hearthlands','Ashstone Badlands',92,70,150,94,'{}');

COMMIT;
PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;
