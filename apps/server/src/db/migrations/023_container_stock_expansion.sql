PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   CONTAINER STOCK EXPANSION (UPDATED)
   Includes your new items: foods, tools, kits, herbs, ammo,
   expanded weapons/armor/shields + a few rare/magic pieces.
   Purpose: make settlements feel fully stocked and varied.
   ========================================================= */

-- =========================================================
-- 1) GENERAL STORE: FRONT SHELF
-- Common travel, food, ammo, small medical, simple tools
-- =========================================================
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_shop_shelf','itm_bread',        6, 20, 45, 1.00, 60,  '{"bucket":"food"}'),
('cdef_shop_shelf','itm_jerky',        5, 18, 40, 1.00, 60,  '{"bucket":"food"}'),
('cdef_shop_shelf','itm_rations',      3, 12, 34, 1.05, 60,  '{"bucket":"food"}'),
('cdef_shop_shelf','itm_cheese',       1,  8, 24, 1.10, 60,  '{"bucket":"food"}'),
('cdef_shop_shelf','itm_honey',        0,  6, 14, 1.15, 90,  '{"bucket":"food"}'),
('cdef_shop_shelf','itm_water_flask',  2,  8, 24, 1.00, 60,  '{"bucket":"drink"}'),

('cdef_shop_shelf','itm_torch',        3, 12, 38, 1.00, 60,  '{"bucket":"travel"}'),
('cdef_shop_shelf','itm_flint_steel',  1,  4, 20, 1.05, 90,  '{"bucket":"travel"}'),
('cdef_shop_shelf','itm_rope',         0,  2, 12, 1.10, 180, '{"bucket":"travel"}'),
('cdef_shop_shelf','itm_lockpicks',    0,  2,  9, 1.15, 240, '{"bucket":"tools","note":"uncommon"}'),

('cdef_shop_shelf','itm_bandage',      2, 12, 28, 1.05, 60,  '{"bucket":"medical"}'),
('cdef_shop_shelf','itm_splint',       0,  6, 18, 1.10, 90,  '{"bucket":"medical"}'),

('cdef_shop_shelf','itm_arrow',       10, 60, 30, 1.00, 60,  '{"bucket":"ammo"}'),
('cdef_shop_shelf','itm_bolt',         5, 40, 22, 1.00, 90,  '{"bucket":"ammo"}'),
('cdef_shop_shelf','itm_pebble',      20, 99, 18, 1.00, 60,  '{"bucket":"ammo"}');

-- =========================================================
-- 2) GENERAL STORE: BACKROOM
-- Materials, components, bulk resources
-- =========================================================
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_shop_backroom','itm_wood',         10, 45, 34, 1.00, 180, '{"bucket":"materials"}'),
('cdef_shop_backroom','itm_stone',         8, 35, 28, 1.00, 180, '{"bucket":"materials"}'),
('cdef_shop_backroom','itm_iron_ore',      4, 20, 22, 1.05, 240, '{"bucket":"materials"}'),
('cdef_shop_backroom','itm_leather',       3, 18, 20, 1.10, 240, '{"bucket":"materials"}'),
('cdef_shop_backroom','itm_cloth',         4, 22, 22, 1.05, 240, '{"bucket":"materials"}'),
('cdef_shop_backroom','itm_meat',          2, 12, 18, 1.05, 90,  '{"bucket":"food","note":"fresh"}'),

('cdef_shop_backroom','itm_thread',        5, 40, 24, 1.05, 240, '{"bucket":"components"}'),
('cdef_shop_backroom','itm_wax',           4, 35, 20, 1.05, 240, '{"bucket":"components"}'),
('cdef_shop_backroom','itm_pitch',         3, 20, 16, 1.05, 240, '{"bucket":"components"}'),
('cdef_shop_backroom','itm_rivets',        3, 25, 18, 1.10, 240, '{"bucket":"components"}'),
('cdef_shop_backroom','itm_leather_strap', 4, 30, 20, 1.05, 240, '{"bucket":"components"}'),
('cdef_shop_backroom','itm_resin',         0, 10, 10, 1.20, 360, '{"bucket":"components","note":"uncommon"}');

-- =========================================================
-- 3) TAVERN PANTRY
-- Heavier on food; some travelers buy supplies here
-- =========================================================
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_tavern_pantry','itm_bread',        6, 24, 40, 1.05, 45, '{"bucket":"food"}'),
('cdef_tavern_pantry','itm_jerky',        6, 22, 36, 1.05, 45, '{"bucket":"food"}'),
('cdef_tavern_pantry','itm_rations',      2, 12, 26, 1.10, 60, '{"bucket":"food"}'),
('cdef_tavern_pantry','itm_cheese',       2, 12, 24, 1.10, 60, '{"bucket":"food"}'),
('cdef_tavern_pantry','itm_honey',        0,  8, 14, 1.15, 90, '{"bucket":"food"}'),
('cdef_tavern_pantry','itm_water_flask',  2, 10, 20, 1.00, 45, '{"bucket":"drink"}'),
('cdef_tavern_pantry','itm_meat',         2, 14, 20, 1.05, 60, '{"bucket":"food","note":"fresh"}');

-- =========================================================
-- 4) SMITH ARMORY
-- Weapons/armor/shields: starter -> respectable town gear
-- =========================================================
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
-- Weapons (starter + expanded)
('cdef_smith_armory','itm_wooden_club',     0,  4, 18, 1.00, 180, '{"bucket":"weapons"}'),
('cdef_smith_armory','itm_training_sword',  0,  4, 18, 1.00, 180, '{"bucket":"weapons"}'),
('cdef_smith_armory','itm_iron_dagger',     0,  4, 22, 1.05, 180, '{"bucket":"weapons"}'),
('cdef_smith_armory','itm_scimitar',        0,  3, 16, 1.05, 240, '{"bucket":"weapons"}'),
('cdef_smith_armory','itm_rapier',          0,  2, 12, 1.10, 300, '{"bucket":"weapons","note":"finesse"}'),
('cdef_smith_armory','itm_iron_sword',      0,  2, 14, 1.10, 300, '{"bucket":"weapons"}'),
('cdef_smith_armory','itm_spear',           0,  3, 14, 1.05, 240, '{"bucket":"weapons"}'),
('cdef_smith_armory','itm_warhammer',       0,  2, 12, 1.10, 300, '{"bucket":"weapons"}'),
('cdef_smith_armory','itm_greatsword',      0,  1,  9, 1.15, 360, '{"bucket":"weapons","note":"two_handed"}'),
('cdef_smith_armory','itm_greataxe',        0,  1,  9, 1.15, 360, '{"bucket":"weapons","note":"two_handed"}'),
('cdef_smith_armory','itm_maul',            0,  1,  8, 1.15, 360, '{"bucket":"weapons","note":"heavy"}'),

-- Ranged weapons
('cdef_smith_armory','itm_short_bow',       0,  2, 12, 1.10, 300, '{"bucket":"weapons","note":"ranged"}'),
('cdef_smith_armory','itm_longbow',         0,  1,  8, 1.15, 360, '{"bucket":"weapons","note":"ranged"}'),
('cdef_smith_armory','itm_crossbow',        0,  1,  8, 1.15, 360, '{"bucket":"weapons","note":"ranged"}'),

-- Light/medium armor
('cdef_smith_armory','itm_cloth_cap',       0,  5, 18, 1.00, 180, '{"bucket":"armor"}'),
('cdef_smith_armory','itm_cloth_tunic',     0,  4, 16, 1.00, 180, '{"bucket":"armor"}'),
('cdef_smith_armory','itm_leather_cap',     0,  4, 16, 1.05, 240, '{"bucket":"armor"}'),
('cdef_smith_armory','itm_leather_vest',    0,  3, 14, 1.10, 240, '{"bucket":"armor"}'),
('cdef_smith_armory','itm_padded_armor',    0,  3, 14, 1.05, 240, '{"bucket":"armor"}'),
('cdef_smith_armory','itm_hide_armor',      0,  2, 12, 1.10, 300, '{"bucket":"armor"}'),
('cdef_smith_armory','itm_scale_mail',      0,  1, 10, 1.15, 360, '{"bucket":"armor","note":"noisy"}'),
('cdef_smith_armory','itm_breastplate',     0,  1,  6, 1.20, 480, '{"bucket":"armor","note":"rare"}'),

-- Heavy armor (rare in shops; more likely city/fort smith)
('cdef_smith_armory','itm_chain_mail',      0,  1,  7, 1.20, 480, '{"bucket":"armor","note":"heavy"}'),
('cdef_smith_armory','itm_plate_armor',     0,  1,  2, 1.35, 720, '{"bucket":"armor","note":"epic_rare"}'),

-- Shields
('cdef_smith_armory','itm_shield_wooden',   0,  3, 14, 1.05, 240, '{"bucket":"shields"}'),
('cdef_smith_armory','itm_shield_steel',    0,  2, 10, 1.10, 300, '{"bucket":"shields"}');

-- =========================================================
-- 5) SMITH TOOL RACK
-- Repair kits + smith materials/components that “make sense”
-- =========================================================
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_smith_toolrack','itm_repair_kit_iron',    1,  5, 24, 1.10, 180, '{"bucket":"repair"}'),
('cdef_smith_toolrack','itm_repair_kit_leather', 1,  5, 22, 1.10, 180, '{"bucket":"repair"}'),
('cdef_smith_toolrack','itm_repair_kit_cloth',   1,  7, 20, 1.05, 180, '{"bucket":"repair"}'),

('cdef_smith_toolrack','itm_iron_ingot',         2, 18, 20, 1.05, 240, '{"bucket":"components"}'),
('cdef_smith_toolrack','itm_iron_ore',           2, 14, 14, 1.05, 240, '{"bucket":"materials"}'),
('cdef_smith_toolrack','itm_rivets',             3, 30, 18, 1.05, 240, '{"bucket":"components"}'),
('cdef_smith_toolrack','itm_leather_strap',      3, 30, 16, 1.05, 240, '{"bucket":"components"}'),
('cdef_smith_toolrack','itm_thread',             4, 40, 16, 1.05, 240, '{"bucket":"components"}'),
('cdef_smith_toolrack','itm_wax',                4, 35, 14, 1.05, 240, '{"bucket":"components"}'),
('cdef_smith_toolrack','itm_pitch',              2, 20, 12, 1.05, 240, '{"bucket":"components"}');

-- =========================================================
-- 6) ALCHEMIST CABINET
-- Herbs + potions + “rare herbs” + occasional focus tonic
-- =========================================================
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
-- Herbs
('cdef_alch_cabinet','itm_healing_herb',   8, 24, 38, 1.00, 120, '{"bucket":"herbs"}'),
('cdef_alch_cabinet','itm_mint_leaf',      8, 30, 34, 1.00, 120, '{"bucket":"herbs"}'),
('cdef_alch_cabinet','itm_sunpetal',       3, 14, 22, 1.10, 180, '{"bucket":"herbs"}'),
('cdef_alch_cabinet','itm_nightshade',     0,  8, 10, 1.25, 360, '{"bucket":"herbs","note":"rare"}'),
('cdef_alch_cabinet','itm_dreamroot',      0,  8, 10, 1.25, 360, '{"bucket":"herbs","note":"rare"}'),

-- Potions
('cdef_alch_cabinet','itm_small_potion',   1,  8, 24, 1.15, 180, '{"bucket":"potions"}'),
('cdef_alch_cabinet','itm_medium_potion',  0,  4, 12, 1.20, 360, '{"bucket":"potions","note":"rare"}'),
('cdef_alch_cabinet','itm_stamina_draught',0,  6, 18, 1.15, 240, '{"bucket":"potions"}'),
('cdef_alch_cabinet','itm_focus_tonic',    0,  3, 10, 1.20, 360, '{"bucket":"potions","note":"rare"}'),

-- Useful cross-over supplies alchemists often carry
('cdef_alch_cabinet','itm_bandage',        1, 10, 12, 1.10, 180, '{"bucket":"medical"}'),
('cdef_alch_cabinet','itm_splint',         0,  6, 10, 1.10, 240, '{"bucket":"medical"}'),
('cdef_alch_cabinet','itm_honey',          0,  6, 10, 1.15, 240, '{"bucket":"food"}');

-- =========================================================
-- 7) VERY RARE / MAGICAL ITEMS
-- We keep weights tiny so they almost never appear in shops.
-- Better approach later: gate by settlement tier/prosperity.
-- =========================================================
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_smith_armory','itm_mithral_shirt',      0, 1,  1, 1.40, 10080, '{"bucket":"armor","note":"rare_magic","shopGate":"city_or_fort"}'),
('cdef_smith_armory','itm_adamantine_plate',  0, 1,  1, 1.60, 20160, '{"bucket":"armor","note":"legendary","shopGate":"capital_only"}'),
('cdef_smith_armory','itm_sunblade',          0, 1,  1, 1.60, 20160, '{"bucket":"weapon","note":"epic_magic","shopGate":"capital_only"}');

COMMIT;
