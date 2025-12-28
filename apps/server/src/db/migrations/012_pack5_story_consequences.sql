PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 5.4 — Story Consequences + Social Graph + No Game Over
   - Capture / retreat / surrender outcomes (never "game over")
   - NPC relationship state machine (friend/rival/companion)
   - Companion table + MAX 2 active companions enforcement
   - Encounter consequence events (structured + AI-readable)
   - Auto world_events logging for encounters + deltas
   ========================================================= */


/* =========================================================
   1) DM/World rules (AI can read + follow)
   ========================================================= */

CREATE TABLE IF NOT EXISTS dm_rules (
  key TEXT PRIMARY KEY,                 -- dm:no_game_over
  value_json TEXT NOT NULL DEFAULT '{}' -- structured config
);

INSERT OR IGNORE INTO dm_rules (key, value_json) VALUES
('dm:no_game_over', '{"enabled":true,"note":"Players never get a hard game over. Failures become story consequences."}'),
('dm:party_companion_limit', '{"maxActiveCompanionsPerPlayer":2}'),
('dm:enemy_defeat_behavior', '{"options":["knocked_out","runs_away","surrenders"],"lootAlwaysDrops":true}'),
('dm:magic_level', '{"style":"medium","note":"Magic exists, but legendary items are rare and meaningful."}'),
('dm:gentle_adaptive', '{"enabled":true,"note":"DM adapts to kids: more hints, softer consequences, always something to do."}');

CREATE VIEW IF NOT EXISTS v_dm_rules AS
SELECT key, value_json FROM dm_rules;


/* =========================================================
   2) NPC relationships (friend/rival/companion) + history deltas
   ========================================================= */

-- Current relationship state (stable summary)
CREATE TABLE IF NOT EXISTS npc_relationships (
  character_id TEXT NOT NULL,
  npc_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'neutral',   -- neutral/friendly/friend/companion/rival/hostile
  affinity INTEGER NOT NULL DEFAULT 0,      -- -100..+100
  trust INTEGER NOT NULL DEFAULT 0,         -- 0..100
  fear INTEGER NOT NULL DEFAULT 0,          -- 0..100
  flags_json TEXT NOT NULL DEFAULT '{}',    -- e.g. {"met":true,"owesFavor":1}
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (character_id, npc_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_npc_relationships_char ON npc_relationships(character_id);
CREATE INDEX IF NOT EXISTS idx_npc_relationships_npc ON npc_relationships(npc_id);

-- Apply relationship_deltas into npc_relationships automatically
CREATE TRIGGER IF NOT EXISTS trg_apply_relationship_delta
AFTER INSERT ON relationship_deltas
BEGIN
  INSERT OR IGNORE INTO npc_relationships (
    character_id, npc_id, status, affinity, trust, fear, flags_json, last_reason, updated_at
  ) VALUES (
    NEW.character_id, NEW.npc_id, 'neutral', 0, 0, 0, '{"met":true}', NEW.reason, NEW.created_at
  );

  UPDATE npc_relationships
     SET affinity   = MAX(-100, MIN(100, affinity + NEW.delta_affinity)),
         trust      = MAX(0,   MIN(100, trust + NEW.delta_trust)),
         fear       = MAX(0,   MIN(100, fear + NEW.delta_fear)),
         last_reason = NEW.reason,
         updated_at  = NEW.created_at
   WHERE character_id = NEW.character_id
     AND npc_id = NEW.npc_id;
END;

-- Auto-update relationship status based on thresholds (simple, kid-friendly)
CREATE TRIGGER IF NOT EXISTS trg_relationship_status_thresholds
AFTER UPDATE OF affinity, trust, fear ON npc_relationships
BEGIN
  UPDATE npc_relationships
     SET status =
       CASE
         WHEN fear >= 70 AND affinity <= -20 THEN 'hostile'
         WHEN affinity <= -50 THEN 'rival'
         WHEN affinity >= 70 AND trust >= 50 THEN 'friend'
         WHEN affinity >= 35 THEN 'friendly'
         ELSE status
       END
   WHERE character_id = NEW.character_id
     AND npc_id = NEW.npc_id;
END;


/* =========================================================
   3) Companions (active cap = 2) + assignments
   ========================================================= */

-- Companion records (NPCs that travel with players)
CREATE TABLE IF NOT EXISTS companions (
  character_id TEXT NOT NULL,
  npc_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'companion', -- companion/pet/hireling
  is_active INTEGER NOT NULL DEFAULT 1,   -- 1 active, 0 inactive (staying behind)
  home_settlement_id TEXT NULL,           -- where they return if inactive
  assigned_building_id TEXT NULL,         -- later: work at your house/settlement building
  meta_json TEXT NOT NULL DEFAULT '{}',
  recruited_at INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (character_id, npc_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE CASCADE,
  FOREIGN KEY (home_settlement_id) REFERENCES settlements_v2(id) ON DELETE SET NULL,
  FOREIGN KEY (assigned_building_id) REFERENCES buildings(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_companions_char ON companions(character_id);
CREATE INDEX IF NOT EXISTS idx_companions_active ON companions(character_id, is_active);

-- Enforce MAX 2 active companions per character
CREATE TRIGGER IF NOT EXISTS trg_companions_max2_insert
BEFORE INSERT ON companions
WHEN NEW.is_active = 1
BEGIN
  SELECT
    CASE
      WHEN (SELECT COUNT(*) FROM companions WHERE character_id = NEW.character_id AND is_active = 1) >=
           (SELECT json_extract(value_json, '$.maxActiveCompanionsPerPlayer') FROM dm_rules WHERE key='dm:party_companion_limit')
      THEN RAISE(ABORT, 'Max active companions reached (2). Make one inactive first.')
    END;
END;

CREATE TRIGGER IF NOT EXISTS trg_companions_max2_update
BEFORE UPDATE OF is_active ON companions
WHEN NEW.is_active = 1
BEGIN
  SELECT
    CASE
      WHEN (SELECT COUNT(*) FROM companions WHERE character_id = NEW.character_id AND is_active = 1 AND npc_id <> NEW.npc_id) >=
           (SELECT json_extract(value_json, '$.maxActiveCompanionsPerPlayer') FROM dm_rules WHERE key='dm:party_companion_limit')
      THEN RAISE(ABORT, 'Max active companions reached (2). Make one inactive first.')
    END;
END;

-- If someone becomes a companion, reflect status in npc_relationships
CREATE TRIGGER IF NOT EXISTS trg_companion_sets_relationship
AFTER INSERT ON companions
BEGIN
  INSERT OR IGNORE INTO npc_relationships (character_id, npc_id, status, affinity, trust, fear, flags_json, last_reason, updated_at)
  VALUES (NEW.character_id, NEW.npc_id, 'companion', 50, 40, 0, '{"met":true,"companion":true}', 'recruited', NEW.recruited_at);

  UPDATE npc_relationships
     SET status = 'companion',
         flags_json = '{"met":true,"companion":true}',
         last_reason = 'recruited',
         updated_at = NEW.recruited_at
   WHERE character_id = NEW.character_id AND npc_id = NEW.npc_id;
END;


/* =========================================================
   4) Encounter outcomes + consequence events (structured)
   ========================================================= */

-- Outcomes are "what happened". Consequences are "what it means".
CREATE TABLE IF NOT EXISTS consequence_defs (
  id TEXT PRIMARY KEY,                  -- cnsq_captured
  name TEXT NOT NULL,
  severity INTEGER NOT NULL DEFAULT 1,  -- 1..10 (gentle)
  meta_json TEXT NOT NULL DEFAULT '{}'  -- tags, suggested followups, etc.
);

INSERT OR IGNORE INTO consequence_defs (id, name, severity, meta_json) VALUES
('cnsq_retreat', 'Retreated', 2, '{"tags":["outcome:retreat"],"followups":["lost_time","new_rumor","enemy_repositions"]}'),
('cnsq_surrender', 'Surrendered', 2, '{"tags":["outcome:surrender"],"followups":["captured_or_bribed","reputation_shift"]}'),
('cnsq_captured', 'Captured (Story)', 4, '{"tags":["outcome:capture"],"followups":["escape_scene","rescue_quest","ransom"]}'),
('cnsq_knocked_out', 'Knocked Out', 3, '{"tags":["outcome:ko"],"followups":["wake_up_somewhere","lose_small_item","new_hook"]}'),
('cnsq_injured', 'Banged Up', 2, '{"tags":["condition:injured"],"followups":["rest","bandage","healer_visit"]}'),
('cnsq_lost_item', 'Lost an Item', 3, '{"tags":["loss:item"],"followups":["recover_stolen_goods","replacement_shop"]}'),
('cnsq_gained_rival', 'Gained a Rival', 3, '{"tags":["social:rival"],"followups":["taunts","ambush_attempt","negotiation"]}'),
('cnsq_made_friend', 'Made a Friend', 2, '{"tags":["social:friend"],"followups":["gift","favor","companion_offer"]}'),
('cnsq_recruited_companion', 'Recruited a Companion', 2, '{"tags":["social:companion"],"followups":["camp_dialogue","bond_event"]}');

CREATE TABLE IF NOT EXISTS encounter_consequences (
  id TEXT PRIMARY KEY,                 -- ecq_xxx
  encounter_run_id TEXT NOT NULL,
  character_id TEXT NULL,
  consequence_def_id TEXT NOT NULL,
  text TEXT NOT NULL DEFAULT '',
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (encounter_run_id) REFERENCES encounter_runs(id) ON DELETE CASCADE,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE SET NULL,
  FOREIGN KEY (consequence_def_id) REFERENCES consequence_defs(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_encounter_conseq_run ON encounter_consequences(encounter_run_id);
CREATE INDEX IF NOT EXISTS idx_encounter_conseq_char ON encounter_consequences(character_id);

-- Optional: quick lookup view for AI
CREATE VIEW IF NOT EXISTS v_encounter_consequence_summary AS
SELECT
  ec.encounter_run_id,
  ec.character_id,
  cd.name AS consequence,
  cd.severity,
  ec.text,
  ec.data_json,
  ec.created_at
FROM encounter_consequences ec
JOIN consequence_defs cd ON cd.id = ec.consequence_def_id;


/* =========================================================
   5) Auto world_events logging (encounters + deltas + consequences)
   ========================================================= */

-- Log encounter completion into world_events (one clean sentence for AI memory)
CREATE TRIGGER IF NOT EXISTS trg_world_event_encounter_complete
AFTER UPDATE OF ended_at, outcome ON encounter_runs
WHEN NEW.ended_at IS NOT NULL AND NEW.ended_at > 0 AND (OLD.ended_at IS NULL OR OLD.ended_at = 0)
BEGIN
  INSERT OR IGNORE INTO world_events (
    id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at
  ) VALUES (
    'evt_enc_' || NEW.id,
    NEW.region_id,
    NEW.settlement_id,
    NEW.poi_id,
    NULL,
    'encounter_complete',
    'Encounter ended: ' || COALESCE(NEW.outcome,'unknown') || '. ' || COALESCE(NEW.summary,''),
    COALESCE(NEW.data_json,'{}'),
    NEW.ended_at
  );
END;

-- Log rep changes (compact)
CREATE TRIGGER IF NOT EXISTS trg_world_event_rep_delta
AFTER INSERT ON rep_deltas
BEGIN
  INSERT OR IGNORE INTO world_events (
    id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at
  ) VALUES (
    'evt_rep_' || NEW.id,
    (SELECT region_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    (SELECT settlement_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    (SELECT poi_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    NEW.character_id,
    'rep_changed',
    'Reputation changed: ' || NEW.target_type || ':' || NEW.target_id ||
    ' score' || CASE WHEN NEW.delta_score >= 0 THEN '+' ELSE '' END || NEW.delta_score ||
    ' (' || COALESCE(NEW.reason,'') || ')',
    '{"targetType":"' || NEW.target_type || '","targetId":"' || NEW.target_id || '","deltaScore":' || NEW.delta_score || '}',
    NEW.created_at
  );
END;

-- Log relationship changes (compact)
CREATE TRIGGER IF NOT EXISTS trg_world_event_relationship_delta
AFTER INSERT ON relationship_deltas
BEGIN
  INSERT OR IGNORE INTO world_events (
    id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at
  ) VALUES (
    'evt_rel_' || NEW.id,
    (SELECT region_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    (SELECT settlement_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    (SELECT poi_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    NEW.character_id,
    'relationship_changed',
    'Relationship changed with ' || NEW.npc_id ||
    ' aff' || CASE WHEN NEW.delta_affinity >= 0 THEN '+' ELSE '' END || NEW.delta_affinity ||
    ' (' || COALESCE(NEW.reason,'') || ')',
    '{"npcId":"' || NEW.npc_id || '","deltaAffinity":' || NEW.delta_affinity || '}',
    NEW.created_at
  );
END;

-- Log consequences
CREATE TRIGGER IF NOT EXISTS trg_world_event_consequence
AFTER INSERT ON encounter_consequences
BEGIN
  INSERT OR IGNORE INTO world_events (
    id, region_id, settlement_id, poi_id, character_id, type, text, data_json, created_at
  ) VALUES (
    'evt_cnsq_' || NEW.id,
    (SELECT region_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    (SELECT settlement_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    (SELECT poi_id FROM encounter_runs WHERE id = NEW.encounter_run_id),
    NEW.character_id,
    'story_consequence',
    (SELECT name FROM consequence_defs WHERE id = NEW.consequence_def_id) || ': ' || COALESCE(NEW.text,''),
    COALESCE(NEW.data_json,'{}'),
    NEW.created_at
  );
END;


/* =========================================================
   6) AI convenience views: social circle + recruitables
   ========================================================= */

-- Social circle snapshot per character
CREATE VIEW IF NOT EXISTS v_character_social_circle AS
SELECT
  nr.character_id,
  nr.npc_id,
  n.name AS npc_name,
  n.role AS npc_role,
  nr.status,
  nr.affinity,
  nr.trust,
  nr.fear,
  nr.last_reason,
  nr.updated_at,
  CASE WHEN c.npc_id IS NOT NULL THEN 1 ELSE 0 END AS is_companion,
  COALESCE(c.is_active, 0) AS companion_active
FROM npc_relationships nr
JOIN npcs n ON n.id = nr.npc_id
LEFT JOIN companions c ON c.character_id = nr.character_id AND c.npc_id = nr.npc_id;

-- “Recruitable” = friendly enough + not already companion + not hostile
CREATE VIEW IF NOT EXISTS v_recruitable_npcs AS
SELECT
  nr.character_id,
  nr.npc_id,
  n.name AS npc_name,
  n.role AS npc_role,
  nr.affinity,
  nr.trust,
  nr.fear,
  nr.status,
  nr.updated_at
FROM npc_relationships nr
JOIN npcs n ON n.id = nr.npc_id
LEFT JOIN companions c ON c.character_id = nr.character_id AND c.npc_id = nr.npc_id
WHERE c.npc_id IS NULL
  AND nr.status IN ('friendly','friend')
  AND nr.fear < 60;


/* =========================================================
   7) Seed: a few story consequence “templates” (optional)
   ========================================================= */

-- These are just common “soft fail” patterns your game can apply.
-- Your server chooses which one, inserts encounter_consequences, and moves on.

CREATE TABLE IF NOT EXISTS consequence_templates (
  id TEXT PRIMARY KEY,                 -- tmpl_capture_rescue
  name TEXT NOT NULL,
  when_outcome TEXT NOT NULL,          -- capture/retreat/surrender/ko
  consequence_def_id TEXT NOT NULL,
  weight INTEGER NOT NULL DEFAULT 10,  -- chance weighting
  text_template TEXT NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (consequence_def_id) REFERENCES consequence_defs(id) ON DELETE RESTRICT
);

INSERT OR IGNORE INTO consequence_templates (id, name, when_outcome, consequence_def_id, weight, text_template, data_json) VALUES
('tmpl_retreat_rumor', 'Retreat -> New Rumor', 'retreat', 'cnsq_retreat', 20,
 'You retreat safely. Back in town, you hear a new rumor about a hidden path.',
 '{"followup":"new_rumor"}'),

('tmpl_capture_ransom', 'Capture -> Ransom', 'capture', 'cnsq_captured', 15,
 'You are captured, but the captors want ransom—not harm. A rescue or bargain is possible.',
 '{"followup":"ransom"}'),

('tmpl_ko_wake_up', 'KO -> Wake Up Somewhere', 'knocked_out', 'cnsq_knocked_out', 25,
 'You wake up later, sore but alive, somewhere unexpected with a new clue nearby.',
 '{"followup":"wake_up_scene"}'),

('tmpl_surrender_trade', 'Surrender -> Trade/Deal', 'surrender', 'cnsq_surrender', 20,
 'You surrender. The enemy lets you go in exchange for a promise… or a small item.',
 '{"followup":"deal"}');


COMMIT;
