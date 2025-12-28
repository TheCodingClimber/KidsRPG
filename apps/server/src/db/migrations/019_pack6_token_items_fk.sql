PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6.x — Pattern B Upgrade
   Add template_token_values.item_def_id (FK -> item_defs)
   and backfill from meta_json.suggestItemDef.
   ========================================================= */

/* 1) Add the column (NULL allowed so non-item tokens still work) */
ALTER TABLE template_token_values
ADD COLUMN item_def_id TEXT NULL;

/* 2) Backfill from meta_json.suggestItemDef if present
      - Works on SQLite with JSON1 enabled (common).
      - Only sets item_def_id when the referenced item exists. */
UPDATE template_token_values
SET item_def_id = json_extract(meta_json, '$.suggestItemDef')
WHERE item_def_id IS NULL
  AND json_extract(meta_json, '$.suggestItemDef') IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM item_defs d
    WHERE d.id = json_extract(template_token_values.meta_json, '$.suggestItemDef')
  );

/* 3) Index for fast lookups */
CREATE INDEX IF NOT EXISTS idx_ttv_item_def
ON template_token_values(item_def_id);

/* 4) Optional: a view to make it dead-simple for your generator
      - Shows a "spawnable" flag and item name when linked */
CREATE VIEW IF NOT EXISTS v_token_values_spawnable AS
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
  v.item_def_id,
  d.name AS item_def_name,
  CASE WHEN v.item_def_id IS NOT NULL THEN 1 ELSE 0 END AS is_spawnable,
  v.meta_json
FROM template_token_values v
JOIN template_token_lists l ON l.id = v.list_id
LEFT JOIN item_defs d ON d.id = v.item_def_id;

/* 5) Optional but recommended: keep meta_json.suggestItemDef in sync
      so old code still works while you transition. */

CREATE TRIGGER IF NOT EXISTS trg_ttv_sync_json_on_item_def
AFTER UPDATE OF item_def_id ON template_token_values
FOR EACH ROW
WHEN NEW.item_def_id IS NOT OLD.item_def_id
BEGIN
  UPDATE template_token_values
  SET meta_json =
    CASE
      WHEN NEW.item_def_id IS NULL THEN
        /* Remove suggestItemDef key if item_def_id cleared */
        json_remove(COALESCE(meta_json, '{}'), '$.suggestItemDef')
      ELSE
        /* Set suggestItemDef to match item_def_id */
        json_set(COALESCE(meta_json, '{}'), '$.suggestItemDef', NEW.item_def_id)
    END
  WHERE id = NEW.id;
END;

COMMIT;
