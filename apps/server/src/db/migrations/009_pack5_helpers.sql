PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 5.2 — Encounter Engine Helpers (Views + Validation)
   Depends on Pack 5.1 tables:
   - encounter_runs, loot_containers, loot_rolls, loot_tables, loot_table_entries
   - reputations, relationships, companion_links
   - world_events, item_instances, containers, container_items, item_defs
   ========================================================= */


/* =========================================================
   0) Canonical event types (consistency = AI sanity)
   ========================================================= */

CREATE TABLE IF NOT EXISTS world_event_types (
  id TEXT PRIMARY KEY,      -- encounter_end, loot_generated, etc.
  label TEXT NOT NULL,
  severity INTEGER NOT NULL DEFAULT 10,  -- 1..100 (for “regional extreme” logic later)
  meta_json TEXT NOT NULL DEFAULT '{}'
);

INSERT OR IGNORE INTO world_event_types (id, label, severity, meta_json) VALUES
('encounter_start', 'Encounter started', 10, '{}'),
('encounter_end', 'Encounter ended', 20, '{}'),
('loot_generated', 'Loot generated', 10, '{}'),
('loot_taken', 'Loot taken', 10, '{}'),
('reputation_changed', 'Reputation changed', 20, '{}'),
('relationship_changed', 'Relationship changed', 20, '{}'),
('status_effect_applied', 'Status effect applied', 10, '{}'),
('companion_recruited', 'Companion recruited', 30, '{}'),
('companion_assigned', 'Companion assigned (party/home/settlement)', 20, '{}'),
('captured', 'Party captured', 50, '{}'),
('retreated', 'Party retreated', 30, '{}'),
('peaceful_resolution', 'Peaceful resolution', 15, '{}');


/* =========================================================
   1) Small utility: “now” provider (lets triggers set timestamps)
   ========================================================= */

-- Your app can UPDATE this table once per “tick” or per request.
-- Triggers can then use (SELECT now_ts FROM game_clock).
CREATE TABLE IF NOT EXISTS game_clock (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  now_ts INTEGER NOT NULL DEFAULT 0
);

INSERT OR IGNORE INTO game_clock (id, now_ts) VALUES (1, 0);


/* =========================================================
   2) Views: Parties, companions, reputation summaries
   ========================================================= */

-- Active companions for each character (max 2 enforced by triggers in Pack 5.1)
CREATE VIEW IF NOT EXISTS v_character_active_companions AS
SELECT
  c.id AS character_id,
  cl.id AS companion_link_id,
  cl.npc_id,
  COALESCE(cl.name_override, n.name, cl.id) AS companion_name,
  cl.role,
  cl.bond,
  cl.assigned_mode,
  cl.assigned_settlement_id,
  cl.assigned_job,
  cl.meta_json
FROM characters c
JOIN companion_links cl
  ON cl.owner_character_id = c.id
 AND cl.is_active = 1
LEFT JOIN npcs n
  ON n.id = cl.npc_id;

-- “Home/settlement” companions for a character (builders/workers/guards)
CREATE VIEW IF NOT EXISTS v_character_home_companions AS
SELECT
  cl.owner_character_id AS character_id,
  cl.id AS companion_link_id,
  cl.npc_id,
  COALESCE(cl.name_override, n.name, cl.id) AS companion_name,
  cl.role,
  cl.bond,
  cl.assigned_settlement_id,
  cl.assigned_job,
  cl.meta_json
FROM companion_links cl
LEFT JOIN npcs n ON n.id = cl.npc_id
WHERE cl.assigned_mode IN ('home','settlement');

-- Reputation summary by “scope”
CREATE VIEW IF NOT EXISTS v_character_reputation_summary AS
SELECT
  r.character_id,
  r.target_type,
  r.target_id,
  r.score,
  r.trust,
  r.fear,
  r.last_reason,
  r.updated_at
FROM reputations r;

-- Regional extreme reputation (only when extreme good/bad)
-- Thresholds: >= 80 or <= -80 (tune later)
CREATE VIEW IF NOT EXISTS v_character_region_extremes AS
SELECT
  r.character_id,
  r.target_id AS region_id,
  r.score,
  r.trust,
  r.fear,
  r.last_reason,
  r.updated_at
FROM reputations r
WHERE r.target_type = 'region'
  AND (r.score >= 80 OR r.score <= -80);


/* =========================================================
   3) Views: Inventory & containers (AI-friendly)
   ========================================================= */

-- Items in a container, resolved to definitions (for “loot container” UI)
CREATE VIEW IF NOT EXISTS v_container_items_detailed AS
SELECT
  ci.container_id,
  ii.id AS item_instance_id,
  ii.item_def_id,
  d.name AS item_name,
  d.type AS item_type,
  d.slot AS item_slot,
  d.rarity,
  ii.qty,
  ii.durability,
  d.durability_max,
  d.weight,
  d.base_value,
  d.meta_json AS def_meta_json,
  ii.rolls_json AS inst_rolls_json
FROM container_items ci
JOIN item_instances ii ON ii.id = ci.item_instance_id
JOIN item_defs d ON d.id = ii.item_def_id;

-- A character’s inventory with definition resolution (includes “equipment” location_type)
CREATE VIEW IF NOT EXISTS v_character_inventory_detailed AS
SELECT
  ii.owner_character_id AS character_id,
  ii.location_type,
  ii.location_id,
  ii.id AS item_instance_id,
  ii.item_def_id,
  d.name AS item_name,
  d.type AS item_type,
  d.slot AS item_slot,
  d.rarity,
  ii.qty,
  ii.durability,
  d.durability_max,
  d.weight,
  d.base_value,
  d.meta_json AS def_meta_json,
  ii.rolls_json AS inst_rolls_json
FROM item_instances ii
JOIN item_defs d ON d.id = ii.item_def_id
WHERE ii.owner_character_id IS NOT NULL;

-- Character encumbrance (simple, stack-aware)
CREATE VIEW IF NOT EXISTS v_character_encumbrance AS
SELECT
  c.id AS character_id,
  c.carry_capacity,
  COALESCE(SUM(d.weight * ii.qty), 0) AS carry_weight
FROM characters c
LEFT JOIN item_instances ii
  ON ii.owner_character_id = c.id
 AND ii.location_type IN ('inventory','equipment')
LEFT JOIN item_defs d
  ON d.id = ii.item_def_id
GROUP BY c.id;


/* =========================================================
   4) Views: Encounter + loot snapshots
   ========================================================= */

-- Encounter run “dashboard”
CREATE VIEW IF NOT EXISTS v_encounter_runs_detailed AS
SELECT
  er.id AS encounter_run_id,
  er.encounter_def_id,
  er.region_id,
  er.poi_id,
  er.settlement_id,
  er.party_json,
  er.started_at,
  er.ended_at,
  er.outcome,
  er.summary,
  er.data_json,
  ed.name AS encounter_name,
  ed.danger AS encounter_danger,
  ed.style AS encounter_style,
  ed.tags_json AS encounter_tags_json
FROM encounter_runs er
LEFT JOIN encounter_defs ed ON ed.id = er.encounter_def_id;

-- Loot containers associated with an encounter run
CREATE VIEW IF NOT EXISTS v_encounter_loot_containers AS
SELECT
  lc.encounter_run_id,
  lc.id AS container_id,
  lc.owner_character_id,
  lc.label,
  lc.generated_at,
  lc.meta_json
FROM loot_containers lc;

-- Loot container items (resolved)
CREATE VIEW IF NOT EXISTS v_encounter_loot_items AS
SELECT
  lc.encounter_run_id,
  lc.id AS container_id,
  v.item_instance_id,
  v.item_def_id,
  v.item_name,
  v.item_type,
  v.rarity,
  v.qty,
  v.base_value,
  v.weight,
  v.def_meta_json,
  v.inst_rolls_json
FROM loot_containers lc
JOIN v_container_items_detailed v
  ON v.container_id = lc.id;

-- Latest world events “memory feed” (for AI context windows)
CREATE VIEW IF NOT EXISTS v_world_events_recent AS
SELECT
  we.id,
  we.region_id,
  we.settlement_id,
  we.poi_id,
  we.character_id,
  we.type,
  we.text,
  we.data_json,
  we.created_at
FROM world_events we
ORDER BY we.created_at DESC;


/* =========================================================
   5) Validation triggers (light guard rails)
   ========================================================= */

-- Ensure encounter_run ended_at is set when outcome moves away from unknown
CREATE TRIGGER IF NOT EXISTS trg_encounter_runs_set_ended_at
AFTER UPDATE OF outcome ON encounter_runs
WHEN NEW.outcome <> 'unknown' AND (NEW.ended_at = 0 OR NEW.ended_at IS NULL)
BEGIN
  UPDATE encounter_runs
     SET ended_at = (SELECT now_ts FROM game_clock WHERE id = 1)
   WHERE id = NEW.id;
END;

-- Ensure loot_container exists as a real container row (ties into your containers table)
-- Pattern: when you insert loot_containers, we auto-create a containers record if missing.
CREATE TRIGGER IF NOT EXISTS trg_loot_containers_create_container
AFTER INSERT ON loot_containers
WHEN (SELECT COUNT(*) FROM containers WHERE id = NEW.id) = 0
BEGIN
  INSERT INTO containers (id, owner_character_id, name, capacity_weight, created_at)
  VALUES (NEW.id, NEW.owner_character_id, NEW.label, 99999.0, NEW.generated_at);
END;

-- Ensure loot container’s container_items rows always reference item_instances located in that container
-- (Prevents “floating loot”)
CREATE TRIGGER IF NOT EXISTS trg_container_items_validate_location
BEFORE INSERT ON container_items
BEGIN
  SELECT
    CASE
      WHEN (SELECT location_type FROM item_instances WHERE id = NEW.item_instance_id) <> 'container'
        OR COALESCE((SELECT location_id FROM item_instances WHERE id = NEW.item_instance_id), '') <> NEW.container_id
      THEN RAISE(ABORT, 'Item instance must have location_type=container and location_id=container_id before linking.')
    END;
END;

-- Optional guard: item_instances with location_type=container must have a location_id
CREATE TRIGGER IF NOT EXISTS trg_item_instances_container_requires_location
BEFORE INSERT ON item_instances
WHEN NEW.location_type = 'container' AND (NEW.location_id IS NULL OR NEW.location_id = '')
BEGIN
  SELECT RAISE(ABORT, 'Container items must set location_id to container_id.');
END;


/* =========================================================
   6) “Staging” helpers: recommended pattern tables (optional)
   ========================================================= */

-- This is a light helper for your server:
-- Insert rows here to describe “planned loot”, then your server can materialize item_instances.
-- It keeps generation deterministic and debuggable.
CREATE TABLE IF NOT EXISTS loot_staging (
  id TEXT PRIMARY KEY,                 -- lstage_xxx
  encounter_run_id TEXT NOT NULL,
  loot_table_id TEXT NOT NULL,
  item_def_id TEXT NOT NULL,
  qty INTEGER NOT NULL DEFAULT 1,
  notes TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (encounter_run_id) REFERENCES encounter_runs(id) ON DELETE CASCADE,
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_loot_staging_run ON loot_staging(encounter_run_id);


COMMIT;
