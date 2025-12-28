PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6.x — AUTOMATIC CONTAINERS (Settlement “Physical Stock”)
   Purpose:
     - Make settlement items exist in actual containers (shelves, chests, wagons)
     - Power shops, taverns, smithies, homes, notice rewards, etc.
     - Keep it simple: containers hold item_instances
   ========================================================= */


/* ---------------------------------------------------------
   1) Container definitions (what kinds exist)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS container_defs (
  id TEXT PRIMARY KEY,                   -- cdef_shop_shelf, cdef_home_chest
  name TEXT NOT NULL,                    -- "Shop Shelf"
  container_type TEXT NOT NULL,          -- shop_shelf, pantry, chest, stash, wagon, armory, altar_box
  default_capacity_weight REAL NOT NULL DEFAULT 99999.0,
  default_capacity_slots  INTEGER NOT NULL DEFAULT 999999,
  access_rule TEXT NOT NULL DEFAULT 'public', -- public/private/locked/owner_only/faction_only
  meta_json TEXT NOT NULL DEFAULT '{}'
);


/* ---------------------------------------------------------
   2) Concrete containers in the world
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS containers (
  id TEXT PRIMARY KEY,                   -- cont_xxx
  container_def_id TEXT NOT NULL,
  owner_type TEXT NOT NULL,              -- settlement/building/npc/character/poi/world
  owner_id TEXT NOT NULL,                -- id based on owner_type
  name TEXT NOT NULL,
  capacity_weight REAL NOT NULL DEFAULT 99999.0,
  capacity_slots  INTEGER NOT NULL DEFAULT 999999,
  is_locked INTEGER NOT NULL DEFAULT 0,
  lock_difficulty INTEGER NOT NULL DEFAULT 0, -- future: lockpicking
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (container_def_id) REFERENCES container_defs(id)
);

CREATE INDEX IF NOT EXISTS idx_containers_owner ON containers(owner_type, owner_id);
CREATE INDEX IF NOT EXISTS idx_containers_def   ON containers(container_def_id);


/* ---------------------------------------------------------
   3) Container ↔ item_instances link (what’s inside)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS container_items (
  container_id TEXT NOT NULL,
  item_instance_id TEXT NOT NULL,
  PRIMARY KEY (container_id, item_instance_id),
  FOREIGN KEY (container_id) REFERENCES containers(id) ON DELETE CASCADE,
  FOREIGN KEY (item_instance_id) REFERENCES item_instances(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_container_items_container ON container_items(container_id);


/* ---------------------------------------------------------
   4) “Auto container” rules: what containers should exist automatically
      Example: every blacksmith building gets an Armory Crate + Tool Rack
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS auto_container_rules (
  id TEXT PRIMARY KEY,                     -- acr_blacksmith_armory
  owner_type TEXT NOT NULL,                -- settlement/building/poi/npc
  owner_match_type TEXT NOT NULL DEFAULT '',-- if owner_type=building, match building.type
  container_def_id TEXT NOT NULL,
  container_name TEXT NOT NULL,
  access_rule_override TEXT NULL,           -- override def access rule
  locked INTEGER NOT NULL DEFAULT 0,
  lock_difficulty INTEGER NOT NULL DEFAULT 0,
  priority INTEGER NOT NULL DEFAULT 10,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (container_def_id) REFERENCES container_defs(id)
);

CREATE INDEX IF NOT EXISTS idx_auto_container_rules_owner
ON auto_container_rules(owner_type, owner_match_type, priority);


/* ---------------------------------------------------------
   5) Container stocking rules (what SHOULD be inside, supports restock)
      You’ll apply this in app logic whenever you restock a container.
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS container_stock_rules (
  container_def_id TEXT NOT NULL,
  item_def_id TEXT NOT NULL,
  min_qty INTEGER NOT NULL DEFAULT 0,
  max_qty INTEGER NOT NULL DEFAULT 5,
  weight INTEGER NOT NULL DEFAULT 10,         -- weighted pick for variable lists
  price_mult REAL NOT NULL DEFAULT 1.0,       -- useful for shop UI pricing
  restock_minutes INTEGER NOT NULL DEFAULT 60,
  meta_json TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY (container_def_id, item_def_id),
  FOREIGN KEY (container_def_id) REFERENCES container_defs(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_container_stock_rules_def ON container_stock_rules(container_def_id);


/* ---------------------------------------------------------
   6) Restock bookkeeping (optional but very useful)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS container_restock_log (
  id TEXT PRIMARY KEY,                 -- crl_xxx
  container_id TEXT NOT NULL,
  restocked_at INTEGER NOT NULL,
  reason TEXT NOT NULL DEFAULT 'timer', -- timer/event/quest/dev
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (container_id) REFERENCES containers(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_container_restock_log ON container_restock_log(container_id, restocked_at);


/* ---------------------------------------------------------
   7) Helpful views for AI + debugging
   --------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_container_summary AS
SELECT
  c.id AS container_id,
  c.name AS container_name,
  cd.container_type,
  c.owner_type,
  c.owner_id,
  c.is_locked,
  c.lock_difficulty,
  COUNT(ci.item_instance_id) AS item_count
FROM containers c
JOIN container_defs cd ON cd.id = c.container_def_id
LEFT JOIN container_items ci ON ci.container_id = c.id
GROUP BY c.id, c.name, cd.container_type, c.owner_type, c.owner_id, c.is_locked, c.lock_difficulty;


/* =========================================================
   SEED: Container defs (common settlement pieces)
   ========================================================= */
INSERT OR IGNORE INTO container_defs
(id, name, container_type, default_capacity_weight, default_capacity_slots, access_rule, meta_json)
VALUES
('cdef_shop_shelf',      'Shop Shelf',      'shop_shelf',  99999, 999999, 'public',     '{"kidFriendly":true}'),
('cdef_shop_backroom',   'Shop Backroom',   'backroom',    99999, 999999, 'owner_only', '{"kidFriendly":true}'),
('cdef_tavern_pantry',   'Tavern Pantry',   'pantry',      99999, 999999, 'owner_only', '{"kidFriendly":true}'),
('cdef_smith_armory',    'Smith Armory',    'armory',      99999, 999999, 'owner_only', '{"kidFriendly":true}'),
('cdef_smith_toolrack',  'Smith Tool Rack', 'toolrack',    99999, 999999, 'owner_only', '{"kidFriendly":true}'),
('cdef_alch_cabinet',    'Alchemist Cabinet','cabinet',    99999, 999999, 'owner_only', '{"kidFriendly":true}'),
('cdef_home_chest',      'Home Chest',      'chest',       99999, 999999, 'private',    '{"kidFriendly":true}'),
('cdef_guard_locker',    'Guard Locker',    'locker',      99999, 999999, 'faction_only','{"kidFriendly":true}'),
('cdef_wagon_trade',     'Trader Wagon',    'wagon',       99999, 999999, 'public',     '{"kidFriendly":true}');


/* =========================================================
   SEED: Auto container rules (by building type)
   Notes:
     - owner_type='building' and owner_match_type matches buildings.type
   ========================================================= */
INSERT OR IGNORE INTO auto_container_rules
(id, owner_type, owner_match_type, container_def_id, container_name, access_rule_override, locked, lock_difficulty, priority, meta_json)
VALUES
-- General store
('acr_general_shelf','building','general','cdef_shop_shelf','Front Shelf',NULL,0,0,20,'{}'),
('acr_general_back','building','general','cdef_shop_backroom','Backroom Stock','owner_only',1,10,10,'{}'),

-- Blacksmith
('acr_smith_armory','building','blacksmith','cdef_smith_armory','Armory Crate','owner_only',1,15,20,'{}'),
('acr_smith_tools','building','blacksmith','cdef_smith_toolrack','Tool Rack','owner_only',0,0,15,'{}'),

-- Tavern
('acr_tavern_pantry','building','tavern','cdef_tavern_pantry','Pantry','owner_only',0,0,20,'{}'),

-- Alchemist
('acr_alch_cabinet','building','alchemist','cdef_alch_cabinet','Potion Cabinet','owner_only',1,12,20,'{}');


/* =========================================================
   SEED: Stock rules (starter examples — expand endlessly)
   ========================================================= */

-- General store shelf: food + basics
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_shop_shelf','itm_bread',  4, 12, 30, 1.00, 60, '{"category":"food"}'),
('cdef_shop_shelf','itm_jerky',  2, 10, 25, 1.00, 60, '{"category":"food"}'),
('cdef_shop_shelf','itm_torch',  2,  6, 20, 1.00, 60, '{"category":"tools"}'),
('cdef_shop_shelf','itm_wood',   6, 20, 20, 1.00, 60, '{"category":"materials"}');

-- Smith armory: gear
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_smith_armory','itm_iron_sword',   0, 2, 12, 1.10, 90, '{"category":"weapon"}'),
('cdef_smith_armory','itm_iron_shield',  0, 2, 10, 1.10, 90, '{"category":"armor"}'),
('cdef_smith_armory','itm_leather_armor',0, 2, 14, 1.05, 90, '{"category":"armor"}');

-- Tool rack: repair stuff
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_smith_toolrack','itm_bandage',  1, 6, 18, 1.10, 90, '{"category":"repair_support"}');

-- Alchemist cabinet
INSERT OR IGNORE INTO container_stock_rules
(container_def_id, item_def_id, min_qty, max_qty, weight, price_mult, restock_minutes, meta_json)
VALUES
('cdef_alch_cabinet','itm_healing_herb', 3, 10, 25, 1.00, 90, '{"category":"ingredients"}'),
('cdef_alch_cabinet','itm_small_potion', 0,  3, 10, 1.20, 90, '{"category":"potions"}');


COMMIT;
