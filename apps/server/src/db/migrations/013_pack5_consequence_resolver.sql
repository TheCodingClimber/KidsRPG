PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 5.5 — Consequence Resolver (Flow Glue)
   Goal:
   - Given an encounter_run + character, return weighted consequence templates
   - Allow weight modifiers (danger, settlement, relationship, luck tags)
   - Keep selection logic app-friendly (DB returns candidates + final weight)
   - Provide a clean "pick query" pattern (2-step) for SQLite
   ========================================================= */


/* =========================================================
   1) Outcome normalization (optional but helpful)
   ========================================================= */

CREATE TABLE IF NOT EXISTS outcome_aliases (
  raw_outcome TEXT PRIMARY KEY,         -- e.g. "captured", "capture", "taken"
  normalized_outcome TEXT NOT NULL      -- capture/retreat/surrender/knocked_out/victory/escape
);

INSERT OR IGNORE INTO outcome_aliases (raw_outcome, normalized_outcome) VALUES
('capture', 'capture'),
('captured', 'capture'),
('taken', 'capture'),
('retreat', 'retreat'),
('fled', 'retreat'),
('run_away', 'retreat'),
('surrender', 'surrender'),
('yielded', 'surrender'),
('knocked_out', 'knocked_out'),
('ko', 'knocked_out'),
('victory', 'victory'),
('won', 'victory'),
('escape', 'escape'),
('escaped', 'escape');


/* =========================================================
   2) Resolver modifiers: rules that adjust template weights
   =========================================================
   The base weight is consequence_templates.weight.
   Modifiers stack in this order:
     - Additive modifiers (weight_add)
     - Multipliers (weight_mult)
   Final weight is clamped to minimum 0.
   ========================================================= */

CREATE TABLE IF NOT EXISTS consequence_weight_mods (
  id TEXT PRIMARY KEY,                     -- cwm_xxx
  template_id TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,

  -- Context matchers (NULL = "don't care")
  normalized_outcome TEXT NULL,            -- capture/retreat/surrender/knocked_out/...
  region_id TEXT NULL,
  settlement_id TEXT NULL,
  poi_id TEXT NULL,

  -- Danger gating (from POI, or encounter meta later)
  min_danger INTEGER NULL,
  max_danger INTEGER NULL,

  -- Relationship gating (optional)
  npc_id TEXT NULL,                        -- if this consequence is about a specific NPC
  min_affinity INTEGER NULL,
  max_affinity INTEGER NULL,
  min_trust INTEGER NULL,
  max_trust INTEGER NULL,
  min_fear INTEGER NULL,
  max_fear INTEGER NULL,
  requires_status TEXT NULL,               -- friendly/friend/companion/rival/hostile

  -- Simple tag gating (string contains check; keeps DB simple)
  requires_tag TEXT NULL,                  -- e.g. "theme:bandits" or "social:rival"

  -- Weight transforms
  weight_add INTEGER NOT NULL DEFAULT 0,   -- +10, -5, etc
  weight_mult REAL NOT NULL DEFAULT 1.0,   -- 1.2, 0.5, etc

  reason TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (template_id) REFERENCES consequence_templates(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_cwm_template ON consequence_weight_mods(template_id);
CREATE INDEX IF NOT EXISTS idx_cwm_outcome ON consequence_weight_mods(normalized_outcome);
CREATE INDEX IF NOT EXISTS idx_cwm_region ON consequence_weight_mods(region_id);
CREATE INDEX IF NOT EXISTS idx_cwm_settlement ON consequence_weight_mods(settlement_id);
CREATE INDEX IF NOT EXISTS idx_cwm_poi ON consequence_weight_mods(poi_id);


/* =========================================================
   3) Simple "luck" input per character (optional)
   =========================================================
   You said: "slightly random as well as luck favors preparation".
   This table lets your app set a session luck value (0..100).
   If you never use it, it does nothing.
   ========================================================= */

CREATE TABLE IF NOT EXISTS character_luck (
  character_id TEXT PRIMARY KEY,
  luck INTEGER NOT NULL DEFAULT 50,        -- 0..100 (default neutral)
  updated_at INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_character_luck_updated ON character_luck(updated_at);


/* =========================================================
   4) Resolver view: candidates with computed final_weight
   =========================================================
   This view returns one row per candidate template *per encounter_run*.
   You can filter by encounter_run_id and (optionally) character_id in your query.
   ========================================================= */

DROP VIEW IF EXISTS v_consequence_candidates;

CREATE VIEW v_consequence_candidates AS
WITH run AS (
  SELECT
    er.id AS encounter_run_id,
    er.region_id,
    er.settlement_id,
    er.poi_id,
    COALESCE(
      (SELECT normalized_outcome FROM outcome_aliases WHERE raw_outcome = er.outcome),
      er.outcome
    ) AS outcome_norm,
    er.data_json AS run_data_json
  FROM encounter_runs er
),
poi_ctx AS (
  SELECT
    p.id AS poi_id,
    p.danger AS poi_danger,
    p.meta_json AS poi_meta_json
  FROM pois p
),
luck_ctx AS (
  SELECT
    cl.character_id,
    cl.luck
  FROM character_luck cl
),
base AS (
  SELECT
    r.encounter_run_id,
    ct.id AS template_id,
    ct.name AS template_name,
    ct.when_outcome,
    ct.consequence_def_id,
    ct.weight AS base_weight,
    ct.text_template,
    ct.data_json AS template_data_json,
    r.region_id,
    r.settlement_id,
    r.poi_id,
    r.outcome_norm,
    COALESCE(pc.poi_danger, 0) AS poi_danger,
    COALESCE(pc.poi_meta_json, '{}') AS poi_meta_json,
    -- Note: character_id is attached later in the final select (so you can join relationships)
    r.run_data_json
  FROM run r
  JOIN consequence_templates ct
    ON ct.when_outcome = r.outcome_norm
  LEFT JOIN poi_ctx pc
    ON pc.poi_id = r.poi_id
),
mods_applied AS (
  SELECT
    b.*,
    cwm.id AS mod_id,
    cwm.weight_add,
    cwm.weight_mult,
    cwm.reason,
    cwm.npc_id,
    cwm.requires_status,
    cwm.min_affinity,
    cwm.max_affinity,
    cwm.min_trust,
    cwm.max_trust,
    cwm.min_fear,
    cwm.max_fear,
    cwm.requires_tag
  FROM base b
  LEFT JOIN consequence_weight_mods cwm
    ON cwm.enabled = 1
   AND cwm.template_id = b.template_id
   AND (cwm.normalized_outcome IS NULL OR cwm.normalized_outcome = b.outcome_norm)
   AND (cwm.region_id IS NULL OR cwm.region_id = b.region_id)
   AND (cwm.settlement_id IS NULL OR cwm.settlement_id = b.settlement_id)
   AND (cwm.poi_id IS NULL OR cwm.poi_id = b.poi_id)
   AND (cwm.min_danger IS NULL OR b.poi_danger >= cwm.min_danger)
   AND (cwm.max_danger IS NULL OR b.poi_danger <= cwm.max_danger)
)
SELECT
  ma.encounter_run_id,
  -- character_id is nullable here; your query typically supplies it and joins relationships
  NULL AS character_id,

  ma.template_id,
  ma.template_name,
  ma.when_outcome,
  ma.consequence_def_id,
  ma.text_template,
  ma.template_data_json,

  ma.region_id,
  ma.settlement_id,
  ma.poi_id,
  ma.outcome_norm,
  ma.poi_danger,
  ma.poi_meta_json,

  ma.base_weight,

  -- If there are multiple mods, we want them aggregated. We do that in the pick query.
  ma.mod_id,
  ma.weight_add,
  ma.weight_mult,
  ma.reason,
  ma.npc_id,
  ma.requires_status,
  ma.min_affinity, ma.max_affinity,
  ma.min_trust, ma.max_trust,
  ma.min_fear, ma.max_fear,
  ma.requires_tag
FROM mods_applied ma;


/* =========================================================
   5) A character-specific view that includes relationship checks
   =========================================================
   SQLite views can't take parameters, so we create a second view that
   returns candidates for *all* character/npc pairs, and your query filters it.
   ========================================================= */

DROP VIEW IF EXISTS v_consequence_candidates_for_character;

CREATE VIEW v_consequence_candidates_for_character AS
WITH candidates AS (
  SELECT * FROM v_consequence_candidates
),
-- Expand candidates across characters (only those who exist in character_luck OR characters)
char_list AS (
  SELECT id AS character_id FROM characters
),
rels AS (
  SELECT
    nr.character_id,
    nr.npc_id,
    nr.status,
    nr.affinity,
    nr.trust,
    nr.fear
  FROM npc_relationships nr
)
SELECT
  c.encounter_run_id,
  cl.character_id,
  c.template_id,
  c.template_name,
  c.when_outcome,
  c.consequence_def_id,
  c.text_template,
  c.template_data_json,
  c.region_id,
  c.settlement_id,
  c.poi_id,
  c.outcome_norm,
  c.poi_danger,
  c.poi_meta_json,
  c.base_weight,
  c.mod_id,
  c.weight_add,
  c.weight_mult,
  c.reason,

  -- relationship fields (only meaningful if mod references an npc_id)
  r.status AS rel_status,
  r.affinity AS rel_affinity,
  r.trust AS rel_trust,
  r.fear AS rel_fear,

  c.npc_id AS mod_npc_id,
  c.requires_status,
  c.min_affinity, c.max_affinity,
  c.min_trust, c.max_trust,
  c.min_fear, c.max_fear,
  c.requires_tag
FROM candidates c
CROSS JOIN char_list cl
LEFT JOIN rels r
  ON r.character_id = cl.character_id
 AND r.npc_id = c.npc_id
WHERE
  -- If a mod specifies npc_id, relationship gates must pass. If no npc_id, skip relationship gating.
  (
    c.npc_id IS NULL
    OR (
      (c.requires_status IS NULL OR r.status = c.requires_status)
      AND (c.min_affinity IS NULL OR r.affinity >= c.min_affinity)
      AND (c.max_affinity IS NULL OR r.affinity <= c.max_affinity)
      AND (c.min_trust   IS NULL OR r.trust   >= c.min_trust)
      AND (c.max_trust   IS NULL OR r.trust   <= c.max_trust)
      AND (c.min_fear    IS NULL OR r.fear    >= c.min_fear)
      AND (c.max_fear    IS NULL OR r.fear    <= c.max_fear)
    )
  )
  -- Tag gating (simple string containment)
  AND (
    c.requires_tag IS NULL
    OR (
      instr(COALESCE(c.poi_meta_json,'{}'), c.requires_tag) > 0
      OR instr(COALESCE(c.template_data_json,'{}'), c.requires_tag) > 0
    )
  );


/* =========================================================
   6) "Pick list" view: aggregates mods and produces final_weight
   =========================================================
   This is the view you’ll typically query from the app.
   ========================================================= */

DROP VIEW IF EXISTS v_consequence_picklist;

CREATE VIEW v_consequence_picklist AS
SELECT
  encounter_run_id,
  character_id,
  template_id,
  template_name,
  when_outcome,
  consequence_def_id,
  text_template,
  template_data_json,
  region_id,
  settlement_id,
  poi_id,
  outcome_norm,
  poi_danger,

  base_weight,

  -- Aggregate modifiers:
  COALESCE(SUM(weight_add), 0) AS total_weight_add,
  COALESCE(EXP(SUM(CASE WHEN weight_mult IS NULL THEN 0 ELSE ln(weight_mult) END)), 1.0) AS total_weight_mult,

  -- Final weight:
  MAX(
    0,
    CAST(ROUND((base_weight + COALESCE(SUM(weight_add),0)) * COALESCE(EXP(SUM(CASE WHEN weight_mult IS NULL THEN 0 ELSE ln(weight_mult) END)),1.0)) AS INTEGER)
  ) AS final_weight,

  -- Helpful debugging/AI:
  json_group_array(
    CASE
      WHEN mod_id IS NULL THEN NULL
      ELSE json_object('modId', mod_id, 'add', weight_add, 'mult', weight_mult, 'reason', reason)
    END
  ) AS mods_json

FROM v_consequence_candidates_for_character
GROUP BY
  encounter_run_id, character_id, template_id;


/* =========================================================
   7) How to pick one (commented, app-friendly)
   =========================================================
   SQLite doesn’t have stored procedures. The clean pattern is:
     A) Get candidates with final_weight > 0
     B) Roll random in your app OR use the weighted SQL below.
   ========================================================= */

-- Example weighted pick query (2-step, copy into your app):
-- 1) Compute total weight
-- SELECT SUM(final_weight) AS total
-- FROM v_consequence_picklist
-- WHERE encounter_run_id = ? AND character_id = ? AND final_weight > 0;

-- 2) Pick one by cumulative weights (app passes :roll between 1..total)
-- SELECT template_id, template_name, consequence_def_id, text_template, template_data_json, final_weight, mods_json
-- FROM (
--   SELECT
--     *,
--     SUM(final_weight) OVER (ORDER BY template_id) AS running_total
--   FROM v_consequence_picklist
--   WHERE encounter_run_id = ? AND character_id = ? AND final_weight > 0
-- )
-- WHERE running_total >= :roll
-- ORDER BY running_total
-- LIMIT 1;

-- NOTE: If your SQLite build doesn't support window functions,
-- do the cumulative logic in your app (recommended anyway).


/* =========================================================
   8) Seed a few useful mods (starter examples)
   ========================================================= */

-- Make "Capture -> Ransom" more likely at higher danger (kid-friendly: drama, not punishment)
INSERT OR IGNORE INTO consequence_weight_mods (
  id, template_id, enabled,
  normalized_outcome, min_danger,
  weight_add, weight_mult, reason
) VALUES
('cwm_capture_ransom_high_danger', 'tmpl_capture_ransom', 1,
 'capture', 40,
 8, 1.0, 'High danger areas favor capture/ransom drama');

-- Make "KO -> Wake Up Somewhere" more likely at mid danger
INSERT OR IGNORE INTO consequence_weight_mods (
  id, template_id, enabled,
  normalized_outcome, min_danger, max_danger,
  weight_add, weight_mult, reason
) VALUES
('cwm_ko_mid_danger', 'tmpl_ko_wake_up', 1,
 'knocked_out', 20, 60,
 6, 1.0, 'Mid danger favors wake-up scenes with clues');

-- Encourage "Retreat -> New Rumor" when POI meta contains bandits
INSERT OR IGNORE INTO consequence_weight_mods (
  id, template_id, enabled,
  normalized_outcome, requires_tag,
  weight_add, weight_mult, reason
) VALUES
('cwm_retreat_bandit_rumor', 'tmpl_retreat_rumor', 1,
 'retreat', 'bandits',
 5, 1.0, 'Bandit areas spawn rumors and alternate routes');


COMMIT;
