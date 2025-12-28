BEGIN;
PRAGMA defer_foreign_keys = ON;
PRAGMA foreign_keys = OFF;

-- =========================================================
-- 002_world_entities.sql (SAFE EXTENSION)
-- Purpose:
--   Extend the world schema WITHOUT conflicting with tables
--   already created in 001_init.sql / 002_world_alive.sql.
--
-- Fixes:
--   - Your DB already has settlements_v2 (created earlier)
--   - That older settlements_v2 does NOT have `tier`
--   - Creating an index on (tier) fails -> "no such column: tier"
-- =========================================================

/* =========================================================
   1) Regions registry (lightweight)
   ========================================================= */

CREATE TABLE IF NOT EXISTS regions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  width INTEGER NULL,
  height INTEGER NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
);

-- Seed the region IDs you already reference (example: 'hearthlands')
-- Safe to re-run
INSERT OR IGNORE INTO regions (id, name, width, height, meta_json) VALUES
('hearthlands', 'Hearthlands', NULL, NULL, '{"notes":"Default starter region"}');


/* =========================================================
   2) settlements_v2 upgrades (ADD tier + timestamps)
   IMPORTANT: settlements_v2 already exists from 002_world_alive.sql
   ========================================================= */

-- Add tier (1..5). This fixes your failing index creation.
ALTER TABLE settlements_v2 ADD COLUMN tier INTEGER NOT NULL DEFAULT 1;

-- Optional bookkeeping (safe defaults; app can update later)
ALTER TABLE settlements_v2 ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE settlements_v2 ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;

-- Helpful indexes (only AFTER column exists)
CREATE INDEX IF NOT EXISTS idx_settlements_v2_region ON settlements_v2(region_id);
CREATE INDEX IF NOT EXISTS idx_settlements_v2_type   ON settlements_v2(type);
CREATE INDEX IF NOT EXISTS idx_settlements_v2_tier   ON settlements_v2(tier);


/* =========================================================
   3) Named regions (rectangles)
   Useful for AI narration + map overlays
   ========================================================= */

CREATE TABLE IF NOT EXISTS named_regions_v1 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  region_id TEXT NOT NULL,
  name TEXT NOT NULL,
  x1 INTEGER NOT NULL,
  y1 INTEGER NOT NULL,
  x2 INTEGER NOT NULL,
  y2 INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (region_id) REFERENCES regions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_named_regions_v1_region ON named_regions_v1(region_id);


COMMIT;
PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;
