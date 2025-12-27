PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 4.2: Gear Systems (Auto-equip helpers, Set Bonuses,
            Affixes, Durability Rules, Repairs)
   Requires Pack 4.1 (equipment_slots + validation triggers)
   ========================================================= */


/* =========================================================
   0) Safety: ensure world_events exists (from 002)
   ========================================================= */
-- If your 002 already created this, this is harmless.
CREATE TABLE IF NOT EXISTS world_events (
  id TEXT PRIMARY KEY,
  region_id TEXT NOT NULL,
  settlement_id TEXT NULL,
  poi_id TEXT NULL,
  character_id TEXT NULL,
  type TEXT NOT NULL,
  text TEXT NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_world_events_character ON world_events(character_id);


/* =========================================================
   1) Auto-equip transaction helpers (DB-enforced syncing)
   =========================================================
   Goal:
   - When an item is equipped:
       item_instances.location_type='equipment'
       item_instances.location_id = slot
   - When unequipped (equipment row set to NULL):
       item_instances.location_type='inventory'
       item_instances.location_id = NULL
   - Log world_events for equip/unequip
*/

-- Ensure these columns exist (from 002). If they already exist, SQLite may error on ALTER.
-- If you already ran 002, COMMENT these out to avoid duplicate-column errors.
-- ALTER TABLE equipment ADD COLUMN item_instance_id TEXT NULL;

-- Equip: on INSERT
CREATE TRIGGER IF NOT EXISTS trg_equipment_apply_insert
AFTER INSERT ON equipment
WHEN NEW.item_instance_id IS NOT NULL
BEGIN
  UPDATE item_instances
  SET location_type = 'equipment',
      location_id   = NEW.slot,
      updated_at    = strftime('%s','now')
  WHERE id = NEW.item_instance_id;

  INSERT INTO world_events (id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at)
  VALUES (
    'evt_' || hex(randomblob(8)),
    'hearthlands',
    NULL,
    NULL,
    NEW.character_id,
    'equipped_item',
    'Equipped item into ' || NEW.slot,
    json_object('slot', NEW.slot, 'item_instance_id', NEW.item_instance_id),
    strftime('%s','now')
  );
END;

-- Equip/Unequip: on UPDATE
CREATE TRIGGER IF NOT EXISTS trg_equipment_apply_update
AFTER UPDATE OF item_instance_id ON equipment
BEGIN
  -- If OLD had an item and NEW is NULL => unequip old item back to inventory
  UPDATE item_instances
  SET location_type = 'inventory',
      location_id   = NULL,
      updated_at    = strftime('%s','now')
  WHERE id = OLD.item_instance_id
    AND OLD.item_instance_id IS NOT NULL
    AND (NEW.item_instance_id IS NULL);

  -- If NEW has an item => mark it as equipped
  UPDATE item_instances
  SET location_type = 'equipment',
      location_id   = NEW.slot,
      updated_at    = strftime('%s','now')
  WHERE id = NEW.item_instance_id
    AND NEW.item_instance_id IS NOT NULL;

  -- Log unequip
  INSERT INTO world_events (id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at)
  SELECT
    'evt_' || hex(randomblob(8)),
    'hearthlands',
    NULL,
    NULL,
    NEW.character_id,
    'unequipped_item',
    'Unequipped item from ' || NEW.slot,
    json_object('slot', NEW.slot, 'item_instance_id', OLD.item_instance_id),
    strftime('%s','now')
  WHERE OLD.item_instance_id IS NOT NULL
    AND NEW.item_instance_id IS NULL;

  -- Log equip (update case)
  INSERT INTO world_events (id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at)
  SELECT
    'evt_' || hex(randomblob(8)),
    'hearthlands',
    NULL,
    NULL,
    NEW.character_id,
    'equipped_item',
    'Equipped item into ' || NEW.slot,
    json_object('slot', NEW.slot, 'item_instance_id', NEW.item_instance_id),
    strftime('%s','now')
  WHERE NEW.item_instance_id IS NOT NULL;
END;


/* =========================================================
   2) Set bonuses (tag-driven)
   =========================================================
   Convention:
     - Items in a set get a tag: set:<set_id>
       e.g. set:explorer, set:iron_oath, set:verdant
     - Bonuses are defined per set and pieces_required.

   AI wins because:
     - it can query equipment -> item_def_tags -> set tags
     - it can reason about "need 1 more piece to activate"
*/

CREATE TABLE IF NOT EXISTS set_defs (
  id TEXT PRIMARY KEY,                 -- set:explorer (id stored without prefix recommended)
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS set_bonuses (
  set_id TEXT NOT NULL,
  pieces_required INTEGER NOT NULL,
  bonus_json TEXT NOT NULL DEFAULT '{}', -- e.g. {"speed":1} or {"hp_max":5}
  PRIMARY KEY (set_id, pieces_required),
  FOREIGN KEY (set_id) REFERENCES set_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_set_bonuses_set ON set_bonuses(set_id);

-- Seed a few sets (you can expand endlessly)
INSERT OR IGNORE INTO set_defs (id, name, description, meta_json) VALUES
('explorer', 'Explorer Set', 'Light gear for curious wanderers.', '{"theme":"travel"}'),
('iron_oath', 'Iron Oath Set', 'Sturdy gear favored by proud smiths.', '{"theme":"craft"}'),
('verdant', 'Verdant Set', 'Nature-touched gear that feels alive.', '{"theme":"nature"}'),
('frostbound', 'Frostbound Set', 'Cold-resisting gear for winter roads.', '{"theme":"ice"}');

-- Seed bonuses
INSERT OR IGNORE INTO set_bonuses (set_id, pieces_required, bonus_json) VALUES
('explorer',   2, '{"speed":1}'),
('explorer',   3, '{"stamina_max":5}'),
('iron_oath',  2, '{"armor":1}'),
('iron_oath',  3, '{"hp_max":5}'),
('verdant',    2, '{"nature_resist":1}'),
('verdant',    3, '{"heal_bonus":1}'),
('frostbound', 2, '{"cold_resist":1}'),
('frostbound', 3, '{"stamina_max":5,"cold_resist":1}');

-- Helpful tags for sets (labels)
INSERT OR IGNORE INTO tags (id, label) VALUES
('set:explorer', 'Set: Explorer'),
('set:iron_oath', 'Set: Iron Oath'),
('set:verdant', 'Set: Verdant'),
('set:frostbound', 'Set: Frostbound');

-- OPTIONAL: Tag a few of your existing items into sets (edit freely)
-- (This is intentionally light; you said you want BIG sets later.)
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_leather_helmet', 'set:explorer'),
('itm_leather_armor',  'set:explorer'),
('itm_feather_boots',  'set:explorer'),

('itm_iron_helmet', 'set:iron_oath'),
('itm_iron_armor',  'set:iron_oath'),
('itm_iron_shield', 'set:iron_oath'),

('itm_bark_armor',  'set:verdant'),
('itm_glow_cloak',  'set:verdant'),

('itm_frost_helm',  'set:frostbound');

-- View: count equipped set pieces per character
CREATE VIEW IF NOT EXISTS v_character_set_piece_counts AS
SELECT
  e.character_id,
  t.tag_id AS set_tag_id,                          -- e.g. set:explorer
  REPLACE(t.tag_id, 'set:', '') AS set_id,         -- explorer
  COUNT(*) AS pieces_equipped
FROM equipment e
JOIN item_instances ii ON ii.id = e.item_instance_id
JOIN item_def_tags t ON t.item_def_id = ii.item_def_id
WHERE e.item_instance_id IS NOT NULL
  AND t.tag_id LIKE 'set:%'
GROUP BY e.character_id, t.tag_id;

-- View: active set bonuses per character (ready for UI + AI)
CREATE VIEW IF NOT EXISTS v_character_active_set_bonuses AS
SELECT
  c.character_id,
  c.set_id,
  c.pieces_equipped,
  b.pieces_required,
  b.bonus_json
FROM v_character_set_piece_counts c
JOIN set_bonuses b
  ON b.set_id = c.set_id
WHERE c.pieces_equipped >= b.pieces_required
ORDER BY c.character_id, c.set_id, b.pieces_required;


/* =========================================================
   3) Item affixes (query-friendly)
   =========================================================
   Convention:
     - item_instances.rolls_json can store: {"affixes":["aff_sturdy","aff_of_sparks"]}
     - We also support a normalized table for easy querying:
         item_instance_affixes(item_instance_id, affix_id)
*/

CREATE TABLE IF NOT EXISTS affix_defs (
  id TEXT PRIMARY KEY,                 -- aff_sturdy
  name TEXT NOT NULL,                  -- "Sturdy"
  rarity TEXT NOT NULL DEFAULT 'common',-- common/uncommon/rare/epic/legendary
  applies_to_types TEXT NOT NULL DEFAULT '[]', -- JSON array e.g. ["weapon","armor","trinket"]
  bonus_json TEXT NOT NULL DEFAULT '{}', -- e.g. {"durability_max":20} or {"damage":1}
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS item_instance_affixes (
  item_instance_id TEXT NOT NULL,
  affix_id TEXT NOT NULL,
  PRIMARY KEY (item_instance_id, affix_id),
  FOREIGN KEY (item_instance_id) REFERENCES item_instances(id) ON DELETE CASCADE,
  FOREIGN KEY (affix_id) REFERENCES affix_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_item_instance_affixes_affix ON item_instance_affixes(affix_id);

-- Seed affixes (kid-safe, fun, simple)
INSERT OR IGNORE INTO affix_defs (id, name, rarity, applies_to_types, bonus_json, meta_json) VALUES
('aff_sturdy',      'Sturdy',      'common',   '["weapon","armor","tool"]', '{"durability_bonus":20}', '{"hint":"Lasts longer before breaking."}'),
('aff_lightweight', 'Lightweight', 'common',   '["weapon","armor","tool"]', '{"weight_mult":0.85}',     '{"hint":"Easier to carry."}'),
('aff_sharp',       'Sharp',       'uncommon', '["weapon"]',               '{"damage":1}',            '{"hint":"A little extra bite."}'),
('aff_balanced',    'Balanced',    'uncommon', '["weapon"]',               '{"accuracy":1}',          '{"hint":"Feels great in the hand."}'),
('aff_guarding',    'Guarding',    'uncommon', '["armor"]',                '{"armor":1}',             '{"hint":"Protects just a bit more."}'),
('aff_of_sparks',   'of Sparks',   'rare',     '["weapon"]',               '{"spark":1}',             '{"hint":"Crackles with friendly lightning."}'),
('aff_of_frost',    'of Frost',    'rare',     '["weapon","armor"]',       '{"cold_resist":1,"slow":1}', '{"hint":"Chilly magic, not scary magic."}'),
('aff_storytold',   'Storytold',   'epic',     '["weapon","trinket"]',     '{"lore":1}',              '{"hint":"Whispers heroic tales."}');

-- View: equipment with affixes
CREATE VIEW IF NOT EXISTS v_character_equipment_with_affixes AS
SELECT
  e.character_id,
  e.slot,
  e.item_instance_id,
  d.id AS item_def_id,
  d.name AS item_name,
  d.type AS item_type,
  d.rarity,
  d.meta_json AS def_meta_json,
  i.rolls_json AS inst_rolls_json,
  COALESCE(
    (SELECT json_group_array(a.affix_id)
     FROM item_instance_affixes a
     WHERE a.item_instance_id = e.item_instance_id),
    '[]'
  ) AS affixes_json
FROM equipment e
LEFT JOIN item_instances i ON i.id = e.item_instance_id
LEFT JOIN item_defs d ON d.id = i.item_def_id;


/* =========================================================
   4) Durability loss rules per action (engine-friendly)
   =========================================================
   Pattern:
     - Game inserts a durability_event row when something happens.
     - DB trigger applies wear to equipped items using rules.

   This keeps logic centralized and consistent.
*/

CREATE TABLE IF NOT EXISTS durability_rules (
  id TEXT PRIMARY KEY,                -- dr_attack_mainhand
  action_type TEXT NOT NULL,          -- attack/blocked_hit/took_hit/mining/chopping/travel
  slot TEXT NULL,                     -- mainhand/offhand/torso/etc or NULL = any
  item_type TEXT NULL,                -- weapon/armor/tool or NULL = any
  chance_pct INTEGER NOT NULL DEFAULT 100,  -- 0..100
  loss_min INTEGER NOT NULL DEFAULT 1,
  loss_max INTEGER NOT NULL DEFAULT 1,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_durability_rules_action ON durability_rules(action_type);

CREATE TABLE IF NOT EXISTS durability_events (
  id TEXT PRIMARY KEY,               -- evtDur_xxx
  character_id TEXT NOT NULL,
  action_type TEXT NOT NULL,
  region_id TEXT NOT NULL DEFAULT 'hearthlands',
  settlement_id TEXT NULL,
  poi_id TEXT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_durability_events_char ON durability_events(character_id);

-- Seed some sane rules (kid-friendly: slow wear, not punishing)
INSERT OR IGNORE INTO durability_rules (id, action_type, slot, item_type, chance_pct, loss_min, loss_max, meta_json) VALUES
('dr_attack_mainhand',   'attack',       'mainhand', 'weapon', 60, 0, 1, '{"note":"Most swings do not damage gear."}'),
('dr_block_offhand',     'blocked_hit',  'offhand',  'armor',  50, 0, 1, '{"note":"Shields wear slowly."}'),
('dr_took_hit_torso',    'took_hit',     'torso',    'armor',  60, 0, 1, '{"note":"Armor scuffs up."}'),
('dr_took_hit_helmet',   'took_hit',     'helmet',   'armor',  30, 0, 1, '{"note":"Helmet rarely takes wear."}'),

('dr_chop_mainhand',     'chopping',     'mainhand', 'weapon', 70, 0, 1, '{"note":"Axes wear a bit when chopping."}'),
('dr_mine_mainhand',     'mining',       'mainhand', 'weapon', 70, 0, 1, '{"note":"Pick/hammer wear a bit when mining."}'),

('dr_travel_feet',       'travel',       'feet',     'armor',  25, 0, 1, '{"note":"Boots wear slowly while traveling."}');

-- Apply durability loss on event
CREATE TRIGGER IF NOT EXISTS trg_apply_durability_on_event
AFTER INSERT ON durability_events
BEGIN
  -- For each equipped item that matches a rule, apply random wear if chance passes.
  -- Wear is bounded so it never goes below 0.
  UPDATE item_instances
  SET durability =
        CASE
          WHEN durability <= 0 THEN 0
          ELSE
            MAX(0, durability - (
              SELECT
                CASE
                  WHEN abs(random()) % 100 < r.chance_pct
                  THEN (
                    r.loss_min +
                    (abs(random()) % (CASE WHEN r.loss_max > r.loss_min THEN (r.loss_max - r.loss_min + 1) ELSE 1 END))
                  )
                  ELSE 0
                END
              FROM durability_rules r
              JOIN equipment e ON e.character_id = NEW.character_id
              JOIN item_instances ii ON ii.id = e.item_instance_id
              JOIN item_defs d ON d.id = ii.item_def_id
              WHERE ii.id = item_instances.id
                AND r.action_type = NEW.action_type
                AND (r.slot IS NULL OR r.slot = e.slot)
                AND (r.item_type IS NULL OR r.item_type = d.type)
              LIMIT 1
            ))
        END,
      updated_at = strftime('%s','now')
  WHERE id IN (
    SELECT ii.id
    FROM equipment e
    JOIN item_instances ii ON ii.id = e.item_instance_id
    JOIN item_defs d ON d.id = ii.item_def_id
    WHERE e.character_id = NEW.character_id
      AND e.item_instance_id IS NOT NULL
      AND d.durability_max > 0
      AND ii.durability > 0
  );

  -- Optional: log "item broke" events
  INSERT INTO world_events (id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at)
  SELECT
    'evt_' || hex(randomblob(8)),
    NEW.region_id,
    NEW.settlement_id,
    NEW.poi_id,
    NEW.character_id,
    'item_broke',
    'An equipped item broke.',
    json_object('action_type', NEW.action_type),
    strftime('%s','now')
  WHERE EXISTS (
    SELECT 1
    FROM equipment e
    JOIN item_instances ii ON ii.id = e.item_instance_id
    JOIN item_defs d ON d.id = ii.item_def_id
    WHERE e.character_id = NEW.character_id
      AND d.durability_max > 0
      AND ii.durability = 0
  );
END;


/* =========================================================
   5) Repair system foundation (rules + events)
   =========================================================
   We’ll keep it DB-consistent and simple:

   - repair_rules defines what kind of kit/station is needed.
   - repair_costs defines item ingredients consumed per repair action.
   - game inserts a repair_event; trigger validates and applies.
   - consumption assumes ingredients exist as inventory stacks for that character.

   If you want perfect multi-stack consumption later, we can upgrade it.
*/

-- Add tags for repair concepts
INSERT OR IGNORE INTO tags (id, label) VALUES
('station:repair', 'Repair Bench'),
('item:repair', 'Repair Item'),
('material:cloth', 'Cloth'),
('material:resin', 'Resin'),
('material:stone', 'Stone');

-- Seed repair materials + kits into item_defs if you don’t have them yet
INSERT OR IGNORE INTO item_defs (id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json) VALUES
('itm_cloth',          'Cloth',          'resource', NULL, 'common',   1, 50, 1, 0.2, 0, '{"tags":["item:resource","material:cloth"]}'),
('itm_resin',          'Resin',          'resource', NULL, 'common',   1, 50, 2, 0.2, 0, '{"tags":["item:resource","material:resin"]}'),
('itm_stone',          'Stone',          'resource', NULL, 'common',   1, 50, 1, 0.6, 0, '{"tags":["item:resource","material:stone"]}'),

('itm_whetstone',      'Whetstone',      'tool',     NULL, 'common',   1, 10, 4, 0.6, 0, '{"tags":["item:repair","tool:repair","repair:weapon"]}'),
('itm_leather_patch',  'Leather Patch',  'tool',     NULL, 'common',   1, 10, 3, 0.2, 0, '{"tags":["item:repair","tool:repair","repair:armor_leather"]}'),
('itm_chain_links',    'Chain Links',    'resource', NULL, 'uncommon', 1, 20, 6, 0.4, 0, '{"tags":["item:repair","repair:armor_chain"]}'),
('itm_iron_rivets',    'Iron Rivets',    'resource', NULL, 'common',   1, 50, 2, 0.1, 0, '{"tags":["item:repair","repair:armor_metal","material:iron"]}'),
('itm_wood_glue',      'Wood Glue',      'tool',     NULL, 'common',   1, 10, 3, 0.3, 0, '{"tags":["item:repair","tool:repair","repair:wood"]}'),
('itm_sewing_kit',     'Sewing Kit',     'tool',     NULL, 'uncommon', 0,  1, 12,0.6, 0, '{"tags":["item:repair","tool:repair","repair:cloth"]}');

-- Link new tags to the tag table for query-ability
INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_cloth', 'material:cloth'),
('itm_resin', 'material:resin'),
('itm_stone', 'material:stone'),
('itm_whetstone', 'item:repair'),
('itm_leather_patch', 'item:repair'),
('itm_chain_links', 'item:repair'),
('itm_iron_rivets', 'item:repair'),
('itm_wood_glue', 'item:repair'),
('itm_sewing_kit', 'item:repair');

CREATE TABLE IF NOT EXISTS repair_rules (
  id TEXT PRIMARY KEY,                 -- rr_weapon_basic
  applies_to_item_type TEXT NOT NULL,  -- weapon/armor/tool
  required_station TEXT NULL,          -- forge/workbench/repair (or NULL for anywhere)
  repair_amount INTEGER NOT NULL DEFAULT 10, -- durability restored per action
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS repair_costs (
  repair_rule_id TEXT NOT NULL,
  item_def_id TEXT NOT NULL,
  qty INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (repair_rule_id, item_def_id),
  FOREIGN KEY (repair_rule_id) REFERENCES repair_rules(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id)
);

CREATE TABLE IF NOT EXISTS repair_events (
  id TEXT PRIMARY KEY,
  character_id TEXT NOT NULL,
  item_instance_id TEXT NOT NULL,
  repair_rule_id TEXT NOT NULL,
  station TEXT NULL,                   -- where repair happened (forge/workbench/repair)
  region_id TEXT NOT NULL DEFAULT 'hearthlands',
  settlement_id TEXT NULL,
  poi_id TEXT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (item_instance_id) REFERENCES item_instances(id) ON DELETE CASCADE,
  FOREIGN KEY (repair_rule_id) REFERENCES repair_rules(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_repair_events_char ON repair_events(character_id);

-- Seed repair rules (simple but expandable)
INSERT OR IGNORE INTO repair_rules (id, applies_to_item_type, required_station, repair_amount, meta_json) VALUES
('rr_weapon_basic', 'weapon', 'forge',     12, '{"hint":"Sharpen, straighten, tighten."}'),
('rr_armor_leather','armor',  'workbench', 12, '{"hint":"Patch, stitch, rebind."}'),
('rr_armor_chain',  'armor',  'forge',     12, '{"hint":"Replace links, hammer dents."}'),
('rr_armor_metal',  'armor',  'forge',     12, '{"hint":"Rivets and careful hammering."}'),
('rr_tool_wood',    'tool',   'workbench', 10, '{"hint":"Glue and rebind handles."}'),
('rr_tool_cloth',   'tool',   'workbench', 10, '{"hint":"Restitch and reinforce."}');

-- Seed costs (tune later)
INSERT OR IGNORE INTO repair_costs (repair_rule_id, item_def_id, qty) VALUES
('rr_weapon_basic', 'itm_whetstone', 1),
('rr_weapon_basic', 'itm_iron_ore',  1),

('rr_armor_leather','itm_leather_patch', 1),
('rr_armor_leather','itm_leather',       1),

('rr_armor_chain',  'itm_chain_links', 1),
('rr_armor_chain',  'itm_iron_ore',    1),

('rr_armor_metal',  'itm_iron_rivets', 2),
('rr_armor_metal',  'itm_iron_ore',    1),

('rr_tool_wood',    'itm_wood_glue', 1),
('rr_tool_wood',    'itm_wood',      1),

('rr_tool_cloth',   'itm_sewing_kit', 1),
('rr_tool_cloth',   'itm_cloth',      2);

-- Repair trigger: validate and apply
CREATE TRIGGER IF NOT EXISTS trg_apply_repair_event
BEFORE INSERT ON repair_events
BEGIN
  -- Must own the item
  SELECT
    CASE
      WHEN (SELECT owner_character_id FROM item_instances WHERE id = NEW.item_instance_id) <> NEW.character_id
      THEN RAISE(ABORT, 'Cannot repair item not owned by character')
    END;

  -- Item must have durability system
  SELECT
    CASE
      WHEN (SELECT d.durability_max
            FROM item_instances i JOIN item_defs d ON d.id = i.item_def_id
            WHERE i.id = NEW.item_instance_id) <= 0
      THEN RAISE(ABORT, 'Item is indestructible; no repair needed')
    END;

  -- Station requirement (if rule requires it)
  SELECT
    CASE
      WHEN (SELECT required_station FROM repair_rules WHERE id = NEW.repair_rule_id) IS NOT NULL
       AND (SELECT required_station FROM repair_rules WHERE id = NEW.repair_rule_id) <> COALESCE(NEW.station,'')
      THEN RAISE(ABORT, 'Wrong station for this repair rule')
    END;

  -- Check ingredients exist in inventory for this character (simple check)
  SELECT
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM repair_costs c
        WHERE c.repair_rule_id = NEW.repair_rule_id
          AND (
            SELECT COALESCE(SUM(ii.qty),0)
            FROM item_instances ii
            WHERE ii.owner_character_id = NEW.character_id
              AND ii.location_type = 'inventory'
              AND ii.item_def_id = c.item_def_id
          ) < c.qty
      )
      THEN RAISE(ABORT, 'Missing repair ingredients')
    END;
END;

-- Apply repair + consume ingredients
CREATE TRIGGER IF NOT EXISTS trg_apply_repair_event_after
AFTER INSERT ON repair_events
BEGIN
  -- Apply durability restore up to max
  UPDATE item_instances
  SET durability = MIN(
        (SELECT d.durability_max FROM item_defs d JOIN item_instances i ON i.item_def_id = d.id WHERE i.id = NEW.item_instance_id),
        durability + (SELECT repair_amount FROM repair_rules WHERE id = NEW.repair_rule_id)
      ),
      updated_at = strftime('%s','now')
  WHERE id = NEW.item_instance_id;

  -- Consume ingredients (simple: subtract from the first matching stack(s))
  -- NOTE: if you have multiple stacks, this reduces one stack per ingredient.
  -- We can upgrade to perfect multi-stack consumption later.
  UPDATE item_instances
  SET qty = qty - (
        SELECT c.qty
        FROM repair_costs c
        WHERE c.repair_rule_id = NEW.repair_rule_id
          AND c.item_def_id = item_instances.item_def_id
      ),
      updated_at = strftime('%s','now')
  WHERE owner_character_id = NEW.character_id
    AND location_type = 'inventory'
    AND item_def_id IN (SELECT item_def_id FROM repair_costs WHERE repair_rule_id = NEW.repair_rule_id)
    AND qty > 0
    AND id IN (
      SELECT ii.id
      FROM item_instances ii
      WHERE ii.owner_character_id = NEW.character_id
        AND ii.location_type = 'inventory'
        AND ii.item_def_id = item_instances.item_def_id
      ORDER BY ii.created_at ASC
      LIMIT 1
    );

  -- Clean up zero stacks
  DELETE FROM item_instances
  WHERE owner_character_id = NEW.character_id
    AND location_type = 'inventory'
    AND qty <= 0;

  -- Log repair
  INSERT INTO world_events (id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at)
  VALUES (
    'evt_' || hex(randomblob(8)),
    NEW.region_id,
    NEW.settlement_id,
    NEW.poi_id,
    NEW.character_id,
    'repaired_item',
    'Repaired an item.',
    json_object('item_instance_id', NEW.item_instance_id, 'repair_rule_id', NEW.repair_rule_id),
    strftime('%s','now')
  );
END;


/* =========================================================
   6) Convenience views for AI + UI
   ========================================================= */

-- Inventory quick view
CREATE VIEW IF NOT EXISTS v_character_inventory AS
SELECT
  ii.owner_character_id AS character_id,
  ii.id AS item_instance_id,
  ii.qty,
  ii.durability,
  ii.quality,
  d.id AS item_def_id,
  d.name AS item_name,
  d.type AS item_type,
  d.rarity,
  d.weight,
  d.durability_max,
  d.meta_json AS def_meta_json,
  ii.rolls_json AS inst_rolls_json
FROM item_instances ii
JOIN item_defs d ON d.id = ii.item_def_id
WHERE ii.owner_character_id IS NOT NULL
  AND ii.location_type = 'inventory';

-- “What set pieces am I missing?” helper view
CREATE VIEW IF NOT EXISTS v_character_set_progress AS
SELECT
  c.character_id,
  s.id AS set_id,
  s.name AS set_name,
  COALESCE(pc.pieces_equipped,0) AS pieces_equipped,
  (SELECT MIN(pieces_required) FROM set_bonuses b WHERE b.set_id = s.id AND b.pieces_required > COALESCE(pc.pieces_equipped,0)) AS next_bonus_at
FROM (SELECT DISTINCT character_id FROM equipment) c
CROSS JOIN set_defs s
LEFT JOIN (
  SELECT character_id, set_id, pieces_equipped
  FROM v_character_set_piece_counts
) pc
  ON pc.character_id = c.character_id AND pc.set_id = s.id;


/* =========================================================
   DONE
   ========================================================= */

COMMIT;
