PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6.x — ITEM SPAWN HELPERS
   Purpose:
     - Convert template tokens into real item_instances
     - Centralize durability, quantity, and source tracking
     - Used by: notices, loot, shops, NPC rewards, encounters
   ========================================================= */


/* ---------------------------------------------------------
   1) Item instances table (if you don’t already have it)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS item_instances (
  id TEXT PRIMARY KEY,                    -- inst_xxx
  item_def_id TEXT NOT NULL,
  owner_type TEXT NULL,                   -- character/npc/settlement/container/world
  owner_id TEXT NULL,                     -- id depending on owner_type
  location_type TEXT NOT NULL DEFAULT 'world',
  location_id TEXT NULL,                  -- settlement_id / poi_id / building_id
  quantity INTEGER NOT NULL DEFAULT 1,
  durability INTEGER NULL,
  durability_max INTEGER NULL,
  source_type TEXT NOT NULL,              -- notice/loot/shop/reward/crafted/event
  source_id TEXT NULL,                    -- notice_id / encounter_id / npc_id
  created_at INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id)
);

CREATE INDEX IF NOT EXISTS idx_item_instances_item
  ON item_instances(item_def_id);

CREATE INDEX IF NOT EXISTS idx_item_instances_owner
  ON item_instances(owner_type, owner_id);

CREATE INDEX IF NOT EXISTS idx_item_instances_location
  ON item_instances(location_type, location_id);


/* ---------------------------------------------------------
   2) Spawn rules (optional tuning per item type)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS item_spawn_rules (
  item_def_id TEXT PRIMARY KEY,
  min_quantity INTEGER NOT NULL DEFAULT 1,
  max_quantity INTEGER NOT NULL DEFAULT 1,
  durability_roll_min REAL NOT NULL DEFAULT 0.7, -- % of max
  durability_roll_max REAL NOT NULL DEFAULT 1.0,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id)
);


/* ---------------------------------------------------------
   3) View: spawnable token values (Pattern B)
   --------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_spawnable_token_items AS
SELECT
  v.id               AS token_value_id,
  v.value            AS display_text,
  v.item_def_id,
  d.name             AS item_name,
  d.stackable,
  d.max_stack,
  d.durability_max,
  COALESCE(r.min_quantity, 1) AS min_qty,
  COALESCE(r.max_quantity, 1) AS max_qty,
  COALESCE(r.durability_roll_min, 1.0) AS dur_min,
  COALESCE(r.durability_roll_max, 1.0) AS dur_max
FROM template_token_values v
JOIN item_defs d ON d.id = v.item_def_id
LEFT JOIN item_spawn_rules r ON r.item_def_id = v.item_def_id;


/* ---------------------------------------------------------
   4) Helper VIEW: resolved spawn roll (AI/app reads this)
   NOTE: SQLite can’t randomize in a VIEW reliably for inserts,
         but this gives your app everything it needs in one query.
   --------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_item_spawn_preview AS
SELECT
  token_value_id,
  item_def_id,
  item_name,
  stackable,
  max_stack,
  durability_max,
  min_qty,
  max_qty,
  dur_min,
  dur_max,
  /* Suggested rolls (app can override if needed) */
  CASE
    WHEN max_qty > min_qty THEN min_qty
    ELSE min_qty
  END AS suggested_qty,
  CASE
    WHEN durability_max IS NOT NULL THEN durability_max
    ELSE NULL
  END AS suggested_durability
FROM v_spawnable_token_items;


/* ---------------------------------------------------------
   5) Example spawn rules (safe defaults)
   --------------------------------------------------------- */
INSERT OR IGNORE INTO item_spawn_rules
(item_def_id, min_quantity, max_quantity, durability_roll_min, durability_roll_max, meta_json)
VALUES
('itm_repair_kit_small', 1, 1, 0.9, 1.0, '{"reason":"reward"}'),
('itm_rope',             1, 2, 1.0, 1.0, '{"reason":"utility"}'),
('itm_torch',            1, 3, 1.0, 1.0, '{"reason":"utility"}'),
('itm_bandage',          1, 3, 1.0, 1.0, '{"reason":"healing"}');


COMMIT;
