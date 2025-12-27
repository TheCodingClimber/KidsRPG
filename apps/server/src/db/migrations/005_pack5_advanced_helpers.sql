PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 5.3 — Advanced Helpers
   - Region extreme rep aggregation
   - Rarity curves by POI danger
   - Luck/prep weighting hooks
   - Encounter recap packet view (AI-ready)
   ========================================================= */


/* =========================================================
   1) Change logs (rep + relationship deltas)
   ========================================================= */

CREATE TABLE IF NOT EXISTS rep_deltas (
  id TEXT PRIMARY KEY,                -- repd_xxx
  character_id TEXT NOT NULL,
  target_type TEXT NOT NULL,          -- faction/settlement/region/npc
  target_id TEXT NOT NULL,
  delta_score INTEGER NOT NULL DEFAULT 0,
  delta_trust INTEGER NOT NULL DEFAULT 0,
  delta_fear INTEGER NOT NULL DEFAULT 0,
  reason TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'system',      -- encounter/quest/dialogue/system
  encounter_run_id TEXT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rep_deltas_char ON rep_deltas(character_id);
CREATE INDEX IF NOT EXISTS idx_rep_deltas_target ON rep_deltas(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_rep_deltas_run ON rep_deltas(encounter_run_id);

CREATE TABLE IF NOT EXISTS relationship_deltas (
  id TEXT PRIMARY KEY,                -- reld_xxx
  character_id TEXT NOT NULL,
  npc_id TEXT NOT NULL,
  delta_affinity INTEGER NOT NULL DEFAULT 0,  -- -100..+100 (your scale)
  delta_trust INTEGER NOT NULL DEFAULT 0,
  delta_fear INTEGER NOT NULL DEFAULT 0,
  reason TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'system',
  encounter_run_id TEXT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_relationship_deltas_char ON relationship_deltas(character_id);
CREATE INDEX IF NOT EXISTS idx_relationship_deltas_npc ON relationship_deltas(npc_id);
CREATE INDEX IF NOT EXISTS idx_relationship_deltas_run ON relationship_deltas(encounter_run_id);


/* =========================================================
   2) Region rep aggregation rules (only when extreme)
   ========================================================= */

-- Settings table (tune without rewriting code)
CREATE TABLE IF NOT EXISTS rep_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  extreme_threshold INTEGER NOT NULL DEFAULT 80,   -- abs(score) >= threshold triggers region echo
  echo_fraction REAL NOT NULL DEFAULT 0.25,        -- 25% of delta echoes into region rep
  max_echo_per_event INTEGER NOT NULL DEFAULT 10   -- clamp echoes so one event can’t nuke a region
);

INSERT OR IGNORE INTO rep_settings (id, extreme_threshold, echo_fraction, max_echo_per_event)
VALUES (1, 80, 0.25, 10);

-- Helper view: “which reputations are extreme”
CREATE VIEW IF NOT EXISTS v_rep_extremes AS
SELECT
  r.character_id,
  r.target_type,
  r.target_id,
  r.score,
  r.trust,
  r.fear,
  r.last_reason,
  r.updated_at,
  (SELECT extreme_threshold FROM rep_settings WHERE id = 1) AS extreme_threshold
FROM reputations r
WHERE ABS(r.score) >= (SELECT extreme_threshold FROM rep_settings WHERE id = 1);

-- When a settlement/faction rep changes AND becomes extreme,
-- echo a portion into region rep (region_id derived from settlement or NPC’s settlement).
-- This trigger is intentionally conservative to keep “medium magic” vibe.

-- Settlement -> Region echo
CREATE TRIGGER IF NOT EXISTS trg_rep_echo_settlement_to_region
AFTER INSERT ON rep_deltas
WHEN NEW.target_type = 'settlement'
BEGIN
  -- Determine region_id from settlements_v2
  INSERT OR IGNORE INTO reputations (character_id, target_type, target_id, score, trust, fear, last_reason, updated_at)
  VALUES (
    NEW.character_id,
    'region',
    (SELECT region_id FROM settlements_v2 WHERE id = NEW.target_id),
    0,0,0,
    'init region rep',
    NEW.created_at
  );

  -- Only echo if settlement rep is currently extreme
  UPDATE reputations
     SET score = score + (
       CASE
         WHEN ABS((SELECT score FROM reputations
                   WHERE character_id = NEW.character_id
                     AND target_type = 'settlement'
                     AND target_id = NEW.target_id)) >= (SELECT extreme_threshold FROM rep_settings WHERE id = 1)
         THEN
           -- clamp( round(delta_score * echo_fraction), -max_echo, +max_echo )
           CASE
             WHEN CAST(ROUND(NEW.delta_score * (SELECT echo_fraction FROM rep_settings WHERE id = 1)) AS INTEGER) > (SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
               THEN (SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
             WHEN CAST(ROUND(NEW.delta_score * (SELECT echo_fraction FROM rep_settings WHERE id = 1)) AS INTEGER) < -(SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
               THEN -(SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
             ELSE CAST(ROUND(NEW.delta_score * (SELECT echo_fraction FROM rep_settings WHERE id = 1)) AS INTEGER)
           END
         ELSE 0
       END
     ),
         last_reason = 'Region echo from extreme settlement rep',
         updated_at = NEW.created_at
   WHERE character_id = NEW.character_id
     AND target_type = 'region'
     AND target_id = (SELECT region_id FROM settlements_v2 WHERE id = NEW.target_id);
END;

-- Faction -> Region echo
-- Uses region from encounter (best), otherwise no-op.
CREATE TRIGGER IF NOT EXISTS trg_rep_echo_faction_to_region
AFTER INSERT ON rep_deltas
WHEN NEW.target_type = 'faction' AND NEW.encounter_run_id IS NOT NULL
BEGIN
  INSERT OR IGNORE INTO reputations (character_id, target_type, target_id, score, trust, fear, last_reason, updated_at)
  VALUES (
    NEW.character_id,
    'region',
    (SELECT region_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    0,0,0,
    'init region rep',
    NEW.created_at
  );

  UPDATE reputations
     SET score = score + (
       CASE
         WHEN ABS((SELECT score FROM reputations
                   WHERE character_id = NEW.character_id
                     AND target_type = 'faction'
                     AND target_id = NEW.target_id)) >= (SELECT extreme_threshold FROM rep_settings WHERE id = 1)
         THEN
           CASE
             WHEN CAST(ROUND(NEW.delta_score * (SELECT echo_fraction FROM rep_settings WHERE id = 1)) AS INTEGER) > (SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
               THEN (SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
             WHEN CAST(ROUND(NEW.delta_score * (SELECT echo_fraction FROM rep_settings WHERE id = 1)) AS INTEGER) < -(SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
               THEN -(SELECT max_echo_per_event FROM rep_settings WHERE id = 1)
             ELSE CAST(ROUND(NEW.delta_score * (SELECT echo_fraction FROM rep_settings WHERE id = 1)) AS INTEGER)
           END
         ELSE 0
       END
     ),
         last_reason = 'Region echo from extreme faction rep',
         updated_at = NEW.created_at
   WHERE character_id = NEW.character_id
     AND target_type = 'region'
     AND target_id = (SELECT region_id FROM encounter_runs WHERE id = NEW.encounter_run_id);
END;


/* =========================================================
   3) Rarity curves by POI danger (medium-magic + kid-friendly)
   ========================================================= */

-- A simple curve table your server can consult:
-- Given danger 1..100 -> weights for rarity outcomes.
-- Your server can use these weights when rolling loot table entries.
CREATE TABLE IF NOT EXISTS loot_rarity_curves (
  id TEXT PRIMARY KEY,               -- curve_default
  name TEXT NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}'  -- stores weights per band
);

-- Bands (danger ranges) stored as JSON for easy tuning:
-- common/uncommon/rare/epic/legendary weights
INSERT OR IGNORE INTO loot_rarity_curves (id, name, meta_json) VALUES
('curve_default', 'Default (Medium Magic)', '{
  "bands":[
    {"min":1,"max":15, "w":{"common":82,"uncommon":16,"rare":2,"epic":0,"legendary":0}},
    {"min":16,"max":35,"w":{"common":72,"uncommon":22,"rare":6,"epic":0,"legendary":0}},
    {"min":36,"max":55,"w":{"common":60,"uncommon":26,"rare":12,"epic":2,"legendary":0}},
    {"min":56,"max":75,"w":{"common":48,"uncommon":28,"rare":18,"epic":6,"legendary":0}},
    {"min":76,"max":90,"w":{"common":38,"uncommon":28,"rare":22,"epic":10,"legendary":2}},
    {"min":91,"max":100,"w":{"common":28,"uncommon":26,"rare":26,"epic":16,"legendary":4}}
  ]
}');


/* =========================================================
   4) Luck / preparation hooks (so “luck favors preparation” works)
   ========================================================= */

-- Player “prep flags” for a run:
-- e.g. brought rope, brought torches, scouted area, asked locals, etc.
CREATE TABLE IF NOT EXISTS encounter_prep_flags (
  encounter_run_id TEXT NOT NULL,
  flag_id TEXT NOT NULL,              -- prep:scouted, prep:torches, prep:rope, prep:healer
  value INTEGER NOT NULL DEFAULT 1,    -- 0/1 or a small count
  note TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (encounter_run_id, flag_id),
  FOREIGN KEY (encounter_run_id) REFERENCES encounter_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_encounter_prep_flags_run ON encounter_prep_flags(encounter_run_id);

-- A tiny catalog of known prep flags (optional but makes AI prompts cleaner)
CREATE TABLE IF NOT EXISTS prep_flag_defs (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  loot_bonus REAL NOT NULL DEFAULT 0.0,    -- affects loot quantity/quality (server-side)
  safety_bonus REAL NOT NULL DEFAULT 0.0,  -- affects surprise/ambush odds (server-side)
  meta_json TEXT NOT NULL DEFAULT '{}'
);

INSERT OR IGNORE INTO prep_flag_defs (id, label, loot_bonus, safety_bonus, meta_json) VALUES
('prep:scouted', 'Scouted the area', 0.10, 0.15, '{"hint":"reduces ambush; better loot choices"}'),
('prep:torches', 'Brought extra torches', 0.05, 0.05, '{"hint":"more exploration success"}'),
('prep:rope', 'Brought rope', 0.05, 0.05, '{"hint":"access hidden ledges/shortcuts"}'),
('prep:healer', 'Healer supplies ready', 0.00, 0.10, '{"hint":"reduces retreat/capture odds"}'),
('prep:bribed_locals', 'Asked/bribed locals for tips', 0.10, 0.00, '{"hint":"finds caches; avoids dead ends"}'),
('prep:map', 'Has a rough map', 0.05, 0.10, '{"hint":"less getting lost"}');


/* =========================================================
   5) Encounter Recap Packet (single query for AI context)
   ========================================================= */

-- This view returns:
-- - encounter run info
-- - POI danger
-- - loot container + items (as compact JSON-ish strings)
-- - rep deltas + relationship deltas (compact)
-- Use it by filtering encounter_run_id in your server.

CREATE VIEW IF NOT EXISTS v_encounter_recap_packet AS
SELECT
  er.id AS encounter_run_id,
  er.region_id,
  er.settlement_id,
  er.poi_id,
  COALESCE(p.danger, 0) AS poi_danger,
  er.encounter_def_id,
  COALESCE(ed.name, '') AS encounter_name,
  COALESCE(ed.style, '') AS encounter_style,
  er.party_json,
  er.started_at,
  er.ended_at,
  er.outcome,
  er.summary,
  er.data_json,

  -- Loot containers count
  (SELECT COUNT(*) FROM loot_containers lc WHERE lc.encounter_run_id = er.id) AS loot_container_count,

  -- Loot items “bundle” (simple string aggregation)
  COALESCE((
    SELECT GROUP_CONCAT(
      d.name || ' x' || ii.qty || ' (' || d.rarity || ')'
    , ' | ')
    FROM loot_containers lc
    JOIN container_items ci ON ci.container_id = lc.id
    JOIN item_instances ii ON ii.id = ci.item_instance_id
    JOIN item_defs d ON d.id = ii.item_def_id
    WHERE lc.encounter_run_id = er.id
  ), '') AS loot_items_summary,

  -- Rep deltas summary
  COALESCE((
    SELECT GROUP_CONCAT(
      rd.target_type || ':' || rd.target_id || ' score' ||
      CASE WHEN rd.delta_score >= 0 THEN '+' ELSE '' END || rd.delta_score ||
      ' (' || rd.reason || ')'
    , ' | ')
    FROM rep_deltas rd
    WHERE rd.encounter_run_id = er.id
  ), '') AS rep_deltas_summary,

  -- Relationship deltas summary
  COALESCE((
    SELECT GROUP_CONCAT(
      rd.npc_id || ' aff' ||
      CASE WHEN rd.delta_affinity >= 0 THEN '+' ELSE '' END || rd.delta_affinity ||
      ' (' || rd.reason || ')'
    , ' | ')
    FROM relationship_deltas rd
    WHERE rd.encounter_run_id = er.id
  ), '') AS relationship_deltas_summary,

  -- Prep flags summary
  COALESCE((
    SELECT GROUP_CONCAT(
      pf.flag_id || '=' || pf.value
    , ', ')
    FROM encounter_prep_flags pf
    WHERE pf.encounter_run_id = er.id
  ), '') AS prep_flags_summary

FROM encounter_runs er
LEFT JOIN pois p ON p.id = er.poi_id
LEFT JOIN encounter_defs ed ON ed.id = er.encounter_def_id;


/* =========================================================
   6) Convenience view: POI danger tier labels (kid-facing)
   ========================================================= */

CREATE VIEW IF NOT EXISTS v_poi_danger_tiers AS
SELECT
  p.id AS poi_id,
  p.region_id,
  p.name,
  p.type,
  p.danger,
  p.recommended_level,
  CASE
    WHEN p.danger <= 15 THEN 'safe-ish'
    WHEN p.danger <= 35 THEN 'risky'
    WHEN p.danger <= 55 THEN 'dangerous'
    WHEN p.danger <= 75 THEN 'very dangerous'
    WHEN p.danger <= 90 THEN 'mythic danger'
    ELSE 'legend danger'
  END AS danger_tier
FROM pois p;


COMMIT;
