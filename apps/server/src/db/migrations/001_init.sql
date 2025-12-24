PRAGMA foreign_keys = ON;

-- Accounts / PIN auth
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Characters
CREATE TABLE IF NOT EXISTS characters (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  name TEXT NOT NULL,
  race TEXT NOT NULL,
  class TEXT NOT NULL,
  background TEXT NOT NULL,
  personality INTEGER NOT NULL DEFAULT 50,
  level INTEGER NOT NULL DEFAULT 1,
  gold INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Saves (where the character is + state)
CREATE TABLE IF NOT EXISTS saves (
  character_id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  state_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

-- Equipment slots (enforced)
CREATE TABLE IF NOT EXISTS equipment (
  character_id TEXT NOT NULL,
  slot TEXT NOT NULL,
  item_id TEXT NULL,
  PRIMARY KEY (character_id, slot),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

-- Inventory items
CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY,
  character_id TEXT NOT NULL,
  name TEXT NOT NULL,
  slot TEXT NOT NULL,          -- e.g. helmet, cloak, trinket, etc.
  rarity TEXT NOT NULL,        -- common, uncommon, rare...
  stats_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

-- Parent-only log for questionable commands
CREATE TABLE IF NOT EXISTS parent_log (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  character_id TEXT NULL,
  created_at INTEGER NOT NULL,
  command_text TEXT NOT NULL,
  context_json TEXT NOT NULL DEFAULT '{}',
  severity INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);
