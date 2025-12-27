PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 4.1: Equipment Slots + Validation (Kid-proof)
   Requires:
   - item_defs, item_instances, item_def_tags, tags (from 002/Pack4)
   - equipment table exists and has:
       character_id, slot (TEXT), and item_instance_id (TEXT) added in 002
   ========================================================= */


/* =========================================================
   1) Equipment slots
   ========================================================= */

CREATE TABLE IF NOT EXISTS equipment_slots (
  id TEXT PRIMARY KEY,                 -- e.g. mainhand, offhand, ring1
  label TEXT NOT NULL,                 -- human-friendly
  sort_order INTEGER NOT NULL DEFAULT 0,
  meta_json TEXT NOT NULL DEFAULT '{}' -- future: ui icons, restrictions, etc.
);

-- Core combat slots + armor
INSERT OR IGNORE INTO equipment_slots (id, label, sort_order) VALUES
('mainhand', 'Main Hand', 10),
('offhand',  'Off Hand',  20),

('helmet',   'Helmet',    30),
('torso',    'Torso',     40),
('back',     'Back',      50),
('feet',     'Feet',      60);

-- Trinket slots (two rings, two charms, one amulet)
INSERT OR IGNORE INTO equipment_slots (id, label, sort_order) VALUES
('ring1',  'Ring 1',  70),
('ring2',  'Ring 2',  80),
('amulet', 'Amulet',  90),
('charm1', 'Charm 1', 100),
('charm2', 'Charm 2', 110);


/* =========================================================
   2) Allowed slot mapping (lets an item fit multiple slots)
   ========================================================= */

CREATE TABLE IF NOT EXISTS item_def_allowed_slots (
  item_def_id TEXT NOT NULL,
  slot_id TEXT NOT NULL,
  PRIMARY KEY (item_def_id, slot_id),
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE,
  FOREIGN KEY (slot_id) REFERENCES equipment_slots(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_item_def_allowed_slots_slot ON item_def_allowed_slots(slot_id);


/* =========================================================
   3) Normalize trinket equip slots (your Pack 4 trinkets had slot=NULL)
   =========================================================
   We convert trinket tag types into item_defs.slot values:
     trinket:ring   -> slot='ring'
     trinket:amulet -> slot='amulet'
     trinket:charm/toy/coin/totem/relic -> slot='charm'
*/

-- Rings
UPDATE item_defs
SET slot = 'ring'
WHERE type = 'trinket'
  AND (slot IS NULL OR slot = '')
  AND id IN (
    SELECT item_def_id FROM item_def_tags WHERE tag_id = 'trinket:ring'
  );

-- Amulets
UPDATE item_defs
SET slot = 'amulet'
WHERE type = 'trinket'
  AND (slot IS NULL OR slot = '')
  AND id IN (
    SELECT item_def_id FROM item_def_tags WHERE tag_id = 'trinket:amulet'
  );

-- Everything else trinket-ish -> charm slot
UPDATE item_defs
SET slot = 'charm'
WHERE type = 'trinket'
  AND (slot IS NULL OR slot = '')
  AND id IN (
    SELECT item_def_id
    FROM item_def_tags
    WHERE tag_id IN ('trinket:charm','trinket:coin','trinket:totem','trinket:relic','trinket:toy')
  );


/* =========================================================
   4) Seed allowed-slot mappings for ALL existing items
   =========================================================
   - Weapons/armor already have item_defs.slot like mainhand/torso/etc
   - Rings go to ring1/ring2
   - Charms go to charm1/charm2
   - Amulets go to amulet
*/

-- Default: if item_defs.slot matches an equipment slot id, allow it there.
INSERT OR IGNORE INTO item_def_allowed_slots (item_def_id, slot_id)
SELECT d.id, d.slot
FROM item_defs d
JOIN equipment_slots s ON s.id = d.slot
WHERE d.slot IS NOT NULL AND d.slot <> '';

-- Rings can go in ring1 or ring2
INSERT OR IGNORE INTO item_def_allowed_slots (item_def_id, slot_id)
SELECT d.id, 'ring1'
FROM item_defs d
WHERE d.type = 'trinket' AND d.slot = 'ring';

INSERT OR IGNORE INTO item_def_allowed_slots (item_def_id, slot_id)
SELECT d.id, 'ring2'
FROM item_defs d
WHERE d.type = 'trinket' AND d.slot = 'ring';

-- Charms can go in charm1 or charm2
INSERT OR IGNORE INTO item_def_allowed_slots (item_def_id, slot_id)
SELECT d.id, 'charm1'
FROM item_defs d
WHERE d.type = 'trinket' AND d.slot = 'charm';

INSERT OR IGNORE INTO item_def_allowed_slots (item_def_id, slot_id)
SELECT d.id, 'charm2'
FROM item_defs d
WHERE d.type = 'trinket' AND d.slot = 'charm';

-- Amulets go in amulet
INSERT OR IGNORE INTO item_def_allowed_slots (item_def_id, slot_id)
SELECT d.id, 'amulet'
FROM item_defs d
WHERE d.type = 'trinket' AND d.slot = 'amulet';


/* =========================================================
   5) Add optional “two-handed” metadata for future weapons
   =========================================================
   Nothing required here, but here’s the convention:
   item_defs.meta_json may include: {"two_handed":1}
   We'll enforce it in triggers below.
   ========================================================= */


/* =========================================================
   6) Validation triggers on equipment
   =========================================================
   Assumptions:
   equipment table has: character_id TEXT, slot TEXT, item_instance_id TEXT
   - One item per (character_id, slot) is your game logic responsibility.
     If you want the DB to enforce it, we add a unique index below.
   ========================================================= */

-- Strongly recommended: only one row per slot per character
CREATE UNIQUE INDEX IF NOT EXISTS ux_equipment_char_slot ON equipment(character_id, slot);

-- Helper: Validate equip attempt (INSERT)
CREATE TRIGGER IF NOT EXISTS trg_equipment_validate_insert
BEFORE INSERT ON equipment
WHEN NEW.item_instance_id IS NOT NULL
BEGIN
  -- Slot must exist
  SELECT
    CASE
      WHEN NOT EXISTS (SELECT 1 FROM equipment_slots WHERE id = NEW.slot)
      THEN RAISE(ABORT, 'Invalid equipment slot')
    END;

  -- Item instance must exist
  SELECT
    CASE
      WHEN NOT EXISTS (SELECT 1 FROM item_instances WHERE id = NEW.item_instance_id)
      THEN RAISE(ABORT, 'Item instance not found')
    END;

  -- Item must be owned by the character
  SELECT
    CASE
      WHEN (SELECT owner_character_id FROM item_instances WHERE id = NEW.item_instance_id) IS NULL
        OR (SELECT owner_character_id FROM item_instances WHERE id = NEW.item_instance_id) <> NEW.character_id
      THEN RAISE(ABORT, 'Cannot equip item not owned by character')
    END;

  -- Cannot equip stackable items
  SELECT
    CASE
      WHEN (SELECT d.stackable
            FROM item_defs d
            JOIN item_instances i ON i.item_def_id = d.id
            WHERE i.id = NEW.item_instance_id) = 1
      THEN RAISE(ABORT, 'Cannot equip stackable item')
    END;

  -- Durability check: if durability_max > 0, instance.durability must be > 0
  SELECT
    CASE
      WHEN (SELECT d.durability_max
            FROM item_defs d
            JOIN item_instances i ON i.item_def_id = d.id
            WHERE i.id = NEW.item_instance_id) > 0
           AND (SELECT i.durability FROM item_instances i WHERE i.id = NEW.item_instance_id) <= 0
      THEN RAISE(ABORT, 'Item is broken (durability 0)')
    END;

  -- Slot compatibility check (must be listed in item_def_allowed_slots)
  SELECT
    CASE
      WHEN NOT EXISTS (
        SELECT 1
        FROM item_instances i
        JOIN item_def_allowed_slots a ON a.item_def_id = i.item_def_id
        WHERE i.id = NEW.item_instance_id
          AND a.slot_id = NEW.slot
      )
      THEN RAISE(ABORT, 'Item cannot be equipped in that slot')
    END;

  -- Two-handed validation:
  -- If equipping a two-handed weapon in mainhand, offhand must be empty.
  SELECT
    CASE
      WHEN NEW.slot = 'mainhand'
       AND (SELECT COALESCE(json_extract(d.meta_json,'$.two_handed'),0)
            FROM item_defs d
            JOIN item_instances i ON i.item_def_id = d.id
            WHERE i.id = NEW.item_instance_id) = 1
       AND EXISTS (
         SELECT 1 FROM equipment e
         WHERE e.character_id = NEW.character_id
           AND e.slot = 'offhand'
           AND e.item_instance_id IS NOT NULL
       )
      THEN RAISE(ABORT, 'Cannot equip two-handed weapon while offhand is occupied')
    END;

  -- Two-handed validation reverse:
  -- If equipping something in offhand, mainhand cannot be two-handed.
  SELECT
    CASE
      WHEN NEW.slot = 'offhand'
       AND EXISTS (
         SELECT 1
         FROM equipment e
         JOIN item_instances mi ON mi.id = e.item_instance_id
         JOIN item_defs md ON md.id = mi.item_def_id
         WHERE e.character_id = NEW.character_id
           AND e.slot = 'mainhand'
           AND COALESCE(json_extract(md.meta_json,'$.two_handed'),0) = 1
       )
      THEN RAISE(ABORT, 'Cannot equip offhand item while wielding two-handed weapon')
    END;
END;

-- Same validations for UPDATE
CREATE TRIGGER IF NOT EXISTS trg_equipment_validate_update
BEFORE UPDATE OF item_instance_id, slot, character_id ON equipment
WHEN NEW.item_instance_id IS NOT NULL
BEGIN
  -- Slot must exist
  SELECT
    CASE
      WHEN NOT EXISTS (SELECT 1 FROM equipment_slots WHERE id = NEW.slot)
      THEN RAISE(ABORT, 'Invalid equipment slot')
    END;

  -- Item instance must exist
  SELECT
    CASE
      WHEN NOT EXISTS (SELECT 1 FROM item_instances WHERE id = NEW.item_instance_id)
      THEN RAISE(ABORT, 'Item instance not found')
    END;

  -- Item must be owned by the character
  SELECT
    CASE
      WHEN (SELECT owner_character_id FROM item_instances WHERE id = NEW.item_instance_id) IS NULL
        OR (SELECT owner_character_id FROM item_instances WHERE id = NEW.item_instance_id) <> NEW.character_id
      THEN RAISE(ABORT, 'Cannot equip item not owned by character')
    END;

  -- Cannot equip stackable items
  SELECT
    CASE
      WHEN (SELECT d.stackable
            FROM item_defs d
            JOIN item_instances i ON i.item_def_id = d.id
            WHERE i.id = NEW.item_instance_id) = 1
      THEN RAISE(ABORT, 'Cannot equip stackable item')
    END;

  -- Durability check
  SELECT
    CASE
      WHEN (SELECT d.durability_max
            FROM item_defs d
            JOIN item_instances i ON i.item_def_id = d.id
            WHERE i.id = NEW.item_instance_id) > 0
           AND (SELECT i.durability FROM item_instances i WHERE i.id = NEW.item_instance_id) <= 0
      THEN RAISE(ABORT, 'Item is broken (durability 0)')
    END;

  -- Slot compatibility
  SELECT
    CASE
      WHEN NOT EXISTS (
        SELECT 1
        FROM item_instances i
        JOIN item_def_allowed_slots a ON a.item_def_id = i.item_def_id
        WHERE i.id = NEW.item_instance_id
          AND a.slot_id = NEW.slot
      )
      THEN RAISE(ABORT, 'Item cannot be equipped in that slot')
    END;

  -- Two-handed validation (same logic as insert)
  SELECT
    CASE
      WHEN NEW.slot = 'mainhand'
       AND (SELECT COALESCE(json_extract(d.meta_json,'$.two_handed'),0)
            FROM item_defs d
            JOIN item_instances i ON i.item_def_id = d.id
            WHERE i.id = NEW.item_instance_id) = 1
       AND EXISTS (
         SELECT 1 FROM equipment e
         WHERE e.character_id = NEW.character_id
           AND e.slot = 'offhand'
           AND e.item_instance_id IS NOT NULL
       )
      THEN RAISE(ABORT, 'Cannot equip two-handed weapon while offhand is occupied')
    END;

  SELECT
    CASE
      WHEN NEW.slot = 'offhand'
       AND EXISTS (
         SELECT 1
         FROM equipment e
         JOIN item_instances mi ON mi.id = e.item_instance_id
         JOIN item_defs md ON md.id = mi.item_def_id
         WHERE e.character_id = NEW.character_id
           AND e.slot = 'mainhand'
           AND COALESCE(json_extract(md.meta_json,'$.two_handed'),0) = 1
       )
      THEN RAISE(ABORT, 'Cannot equip offhand item while wielding two-handed weapon')
    END;
END;


/* =========================================================
   7) “Nice to have”: a view to help UI + AI reasoning
   ========================================================= */

CREATE VIEW IF NOT EXISTS v_character_equipment AS
SELECT
  e.character_id,
  e.slot,
  e.item_instance_id,
  d.id   AS item_def_id,
  d.name AS item_name,
  d.type AS item_type,
  d.rarity,
  d.weight,
  d.durability_max,
  i.durability,
  d.meta_json AS def_meta_json,
  i.rolls_json AS inst_rolls_json
FROM equipment e
LEFT JOIN item_instances i ON i.id = e.item_instance_id
LEFT JOIN item_defs d ON d.id = i.item_def_id;


COMMIT;
