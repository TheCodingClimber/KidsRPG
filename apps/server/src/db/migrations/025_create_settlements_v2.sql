PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS settlements_v2 (
  id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,

  tier INTEGER NOT NULL DEFAULT 2,        -- 1-5
  prosperity INTEGER NOT NULL DEFAULT 50, -- 0-100

  meta_json TEXT NOT NULL DEFAULT '{}',

  created_at INTEGER NOT NULL DEFAULT (unixepoch() * 1000),
  updated_at INTEGER NOT NULL DEFAULT (unixepoch() * 1000)
);

CREATE INDEX IF NOT EXISTS idx_settlements_v2_region ON settlements_v2(region_id);
CREATE INDEX IF NOT EXISTS idx_settlements_v2_type ON settlements_v2(type);
CREATE INDEX IF NOT EXISTS idx_settlements_v2_tier ON settlements_v2(tier);
