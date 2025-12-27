PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 5.1 — Encounters, Outcomes, Loot, Reputation, Companions
   Based on your answers:
   - Descriptive outcomes + hooks for systemic consequences
   - Loot: container-based + choice
   - Reputation: NPC + faction + settlement (+ regional extreme)
   - Companions: 2 active per player + home/settlement worker roles
   - Gentle injuries/status effects (optional light C)
   ========================================================= */


/* =========================================================
   1) Reputation + relationships (AI-reasonable)
   ========================================================= */

-- Character reputation toward: NPCs, factions, settlements, regions.
-- score suggested range: -100..+100
CREATE TABLE IF NOT EXISTS reputations (
  character_id TEXT NOT NULL,
  target_type TEXT NOT NULL,   -- npc / faction / settlement / region
  target_id TEXT NOT NULL,
  score INTEGER NOT NULL DEFAULT 0,
  trust INTEGER NOT NULL DEFAULT 0,          -- separate axis (useful for recruitment)
  fear INTEGER NOT NULL DEFAULT 0,           -- optional: intimidation effects
  last_reason TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (character_id, target_type, target_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_reputations_target ON reputations(target_type, target_id);

-- Relationship memories (for recurring rivals/friends, “enemy remembers you”)
CREATE TABLE IF NOT EXISTS relationships (
  character_id TEXT NOT NULL,
  other_type TEXT NOT NULL,    -- npc / character / creature (future) / faction (optional)
  other_id TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'neutral', -- neutral/friendly/rival/hostile/ally
  affinity INTEGER NOT NULL DEFAULT 0,    -- -100..+100
  notes TEXT NOT NULL DEFAULT '',         -- short human-readable note
  flags_json TEXT NOT NULL DEFAULT '{}',  -- e.g. {"spared":1,"humiliated":0}
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (character_id, other_type, other_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_relationships_other ON relationships(other_type, other_id);


/* =========================================================
   2) Encounters + outcomes (descriptive with structured hooks)
   ========================================================= */

CREATE TABLE IF NOT EXISTS encounter_defs (
  id TEXT PRIMARY KEY,                 -- enc_bandits_road_01
  region_id TEXT NOT NULL,
  poi_id TEXT NULL,
  settlement_id TEXT NULL,
  name TEXT NOT NULL,
  danger INTEGER NOT NULL DEFAULT 10,   -- 1..100 (ties into your danger scaling)
  style TEXT NOT NULL DEFAULT 'classic',-- classic/mythic/etc (future)
  tags_json TEXT NOT NULL DEFAULT '[]', -- ["humanoid","bandit","ambush"]
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_encounter_defs_region ON encounter_defs(region_id);
CREATE INDEX IF NOT EXISTS idx_encounter_defs_poi ON encounter_defs(poi_id);

-- Each time a party hits an encounter
CREATE TABLE IF NOT EXISTS encounter_runs (
  id TEXT PRIMARY KEY,                 -- run_xxx
  encounter_def_id TEXT NULL,
  region_id TEXT NOT NULL,
  poi_id TEXT NULL,
  settlement_id TEXT NULL,
  party_json TEXT NOT NULL DEFAULT '[]',   -- ["char_a","char_b",...]
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL DEFAULT 0,
  outcome TEXT NOT NULL DEFAULT 'unknown', -- win/retreat/captured/surrendered/enemy_fled/peace
  summary TEXT NOT NULL DEFAULT '',        -- kid-safe narration
  data_json TEXT NOT NULL DEFAULT '{}',    -- structured hooks for AI
  FOREIGN KEY (encounter_def_id) REFERENCES encounter_defs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_encounter_runs_region ON encounter_runs(region_id);
CREATE INDEX IF NOT EXISTS idx_encounter_runs_poi ON encounter_runs(poi_id);
CREATE INDEX IF NOT EXISTS idx_encounter_runs_settlement ON encounter_runs(settlement_id);


/* =========================================================
   3) Loot: tables + “loot container” output (choice-based)
   ========================================================= */

CREATE TABLE IF NOT EXISTS loot_tables (
  id TEXT PRIMARY KEY,                 -- lt_bandits_low
  name TEXT NOT NULL,
  min_rolls INTEGER NOT NULL DEFAULT 1,
  max_rolls INTEGER NOT NULL DEFAULT 3,
  gold_min INTEGER NOT NULL DEFAULT 0,
  gold_max INTEGER NOT NULL DEFAULT 0,
  tags_json TEXT NOT NULL DEFAULT '[]', -- ["humanoid","bandit"]
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS loot_table_entries (
  loot_table_id TEXT NOT NULL,
  item_def_id TEXT NOT NULL,
  weight INTEGER NOT NULL DEFAULT 10,   -- chance weight
  qty_min INTEGER NOT NULL DEFAULT 1,
  qty_max INTEGER NOT NULL DEFAULT 1,
  rarity_hint TEXT NOT NULL DEFAULT 'common', -- used for AI explanation, not enforcement
  PRIMARY KEY (loot_table_id, item_def_id),
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE,
  FOREIGN KEY (item_def_id) REFERENCES item_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_loot_entries_table ON loot_table_entries(loot_table_id);

-- Loot containers created by encounters (ties into your existing containers/container_items/item_instances)
CREATE TABLE IF NOT EXISTS loot_containers (
  id TEXT PRIMARY KEY,                 -- loot_xxx (also a container_id)
  encounter_run_id TEXT NOT NULL,
  owner_character_id TEXT NULL,        -- NULL means “party loot”
  label TEXT NOT NULL DEFAULT 'Loot',
  generated_at INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (encounter_run_id) REFERENCES encounter_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_loot_containers_run ON loot_containers(encounter_run_id);

-- Optional: record the “roll history” for debugging + AI narration
CREATE TABLE IF NOT EXISTS loot_rolls (
  id TEXT PRIMARY KEY,                 -- lroll_xxx
  encounter_run_id TEXT NOT NULL,
  loot_table_id TEXT NOT NULL,
  rolls_json TEXT NOT NULL DEFAULT '[]', -- e.g. [{"item":"itm_bread","qty":2},...]
  gold_awarded INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (encounter_run_id) REFERENCES encounter_runs(id) ON DELETE CASCADE,
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_loot_rolls_run ON loot_rolls(encounter_run_id);


/* =========================================================
   4) Gentle injuries: status effects (light C)
   ========================================================= */

CREATE TABLE IF NOT EXISTS status_effect_defs (
  id TEXT PRIMARY KEY,                 -- se_tired
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'debuff', -- buff/debuff/neutral
  duration_minutes INTEGER NOT NULL DEFAULT 60,
  meta_json TEXT NOT NULL DEFAULT '{}' -- {"stamina_max_delta":-2}
);

CREATE TABLE IF NOT EXISTS character_status_effects (
  id TEXT PRIMARY KEY,                 -- cse_xxx
  character_id TEXT NOT NULL,
  status_effect_id TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ends_at INTEGER NOT NULL,
  source TEXT NOT NULL DEFAULT '',     -- encounter/run/food/etc
  data_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (status_effect_id) REFERENCES status_effect_defs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_cse_character ON character_status_effects(character_id);
CREATE INDEX IF NOT EXISTS idx_cse_ends ON character_status_effects(ends_at);


/* =========================================================
   5) Companions: active slots + home/settlement workers
   ========================================================= */

-- Companion “entity” is initially NPC-based (later can expand to creatures/constructs/etc)
CREATE TABLE IF NOT EXISTS companion_links (
  id TEXT PRIMARY KEY,                 -- comp_xxx
  owner_character_id TEXT NOT NULL,
  npc_id TEXT NULL,                    -- optional: companion is an NPC
  name_override TEXT NULL,             -- if renamed
  role TEXT NOT NULL DEFAULT 'ally',   -- ally/pet/hireling/rival_turned
  bond INTEGER NOT NULL DEFAULT 0,     -- 0..100
  is_active INTEGER NOT NULL DEFAULT 0,
  assigned_mode TEXT NOT NULL DEFAULT 'party', -- party/home/settlement
  assigned_settlement_id TEXT NULL,    -- where they work/live (future build system)
  assigned_job TEXT NULL,              -- builder/guard/farmer/merchant/etc
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (owner_character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE SET NULL,
  FOREIGN KEY (assigned_settlement_id) REFERENCES settlements_v2(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_companions_owner ON companion_links(owner_character_id);
CREATE INDEX IF NOT EXISTS idx_companions_active ON companion_links(owner_character_id, is_active);

-- Enforce: max 2 active companions per player character
CREATE TRIGGER IF NOT EXISTS trg_companions_max2_active_insert
BEFORE INSERT ON companion_links
WHEN NEW.is_active = 1
BEGIN
  SELECT
    CASE
      WHEN (SELECT COUNT(*) FROM companion_links
            WHERE owner_character_id = NEW.owner_character_id
              AND is_active = 1) >= 2
      THEN RAISE(ABORT, 'Max 2 active companions per character.')
    END;
END;

CREATE TRIGGER IF NOT EXISTS trg_companions_max2_active_update
BEFORE UPDATE OF is_active ON companion_links
WHEN NEW.is_active = 1 AND OLD.is_active = 0
BEGIN
  SELECT
    CASE
      WHEN (SELECT COUNT(*) FROM companion_links
            WHERE owner_character_id = NEW.owner_character_id
              AND is_active = 1) >= 2
      THEN RAISE(ABORT, 'Max 2 active companions per character.')
    END;
END;


/* =========================================================
   6) “AI inventory reasoning rules” (lightweight + practical)
   ========================================================= */

-- Think of this as “how the AI should talk about item value/use”.
-- Example: “Bandages are best when HP < 50%”, “Torches are useful in caves”.
CREATE TABLE IF NOT EXISTS ai_rules (
  id TEXT PRIMARY KEY,                  -- airule_bandage_low_hp
  scope TEXT NOT NULL,                  -- item / tag / shop / encounter / general
  subject_id TEXT NOT NULL,             -- item_def_id or tag_id or shop_id etc
  rule_type TEXT NOT NULL,              -- prefer/avoid/explain/suggest/priority
  priority INTEGER NOT NULL DEFAULT 50,  -- higher wins
  condition_json TEXT NOT NULL DEFAULT '{}', -- {"hp_pct_lt":0.5}
  effect_json TEXT NOT NULL DEFAULT '{}',    -- {"suggest":"use","reason":"..."}
  text TEXT NOT NULL DEFAULT '',         -- kid-safe explanation line
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_ai_rules_scope_subject ON ai_rules(scope, subject_id);


/* =========================================================
   7) Seed data: gentle status effects + loot tables starter
   ========================================================= */

INSERT OR IGNORE INTO status_effect_defs (id, name, description, kind, duration_minutes, meta_json) VALUES
('se_tired',  'Tired',  'You feel a bit worn out. A rest or warm tea will help.', 'debuff', 90,  '{"stamina_max_delta":-2}'),
('se_sore',   'Sore',   'Your muscles ache a little. Rest helps you bounce back.',  'debuff', 120, '{"hp_max_delta":-1}'),
('se_brave',  'Brave',  'You feel courageous after a victory!',                   'buff',   60,  '{"fear_delta":-5}'),
('se_lucky',  'Lucky',  'Things seem to go your way for a while.',               'buff',   45,  '{"loot_bonus_hint":1}');

-- NOTE: Your current item_defs referenced itm_meat and itm_cloth in recipes but those items
-- were not defined in the snippet. We define them here so your recipes won’t break.
INSERT OR IGNORE INTO item_defs (id, name, type, slot, rarity, stackable, max_stack, base_value, weight, durability_max, meta_json) VALUES
('itm_cloth', 'Cloth', 'resource', NULL, 'common', 1, 50, 1, 0.2, 0, '{"tags":["item:resource","material:cloth"]}'),
('itm_meat',  'Meat',  'resource', NULL, 'common', 1, 20, 2, 0.4, 0, '{"tags":["item:resource","item:food"]}'),
('itm_coin_pouch', 'Coin Pouch', 'trinket', NULL, 'common', 0, 1, 5, 0.1, 0, '{"tags":["item:trinket"],"flavor":"Keeps your coins from jingling too loudly."}');

INSERT OR IGNORE INTO tags (id, label) VALUES
('material:cloth', 'Cloth'),
('item:trinket', 'Trinket');

INSERT OR IGNORE INTO item_def_tags (item_def_id, tag_id) VALUES
('itm_cloth', 'material:cloth'),
('itm_coin_pouch', 'item:trinket');

-- Loot tables (starter): bandits low/mid, beasts low
INSERT OR IGNORE INTO loot_tables (id, name, min_rolls, max_rolls, gold_min, gold_max, tags_json, meta_json) VALUES
('lt_bandits_low', 'Bandits (Low)', 1, 3, 3, 12, '["humanoid","bandit","low"]', '{"notes":"Common roadside troublemakers."}'),
('lt_bandits_mid', 'Bandits (Mid)', 2, 4, 8, 25, '["humanoid","bandit","mid"]', '{"notes":"Better equipped and organized."}'),
('lt_beasts_low',  'Beasts (Low)',  1, 2, 0,  3, '["beast","low"]',            '{"notes":"Wild critters and cave nuisances."}');

-- Loot entries (keep kid-safe and useful)
INSERT OR IGNORE INTO loot_table_entries (loot_table_id, item_def_id, weight, qty_min, qty_max, rarity_hint) VALUES
-- bandits low
('lt_bandits_low', 'itm_bread', 18, 1, 2, 'common'),
('lt_bandits_low', 'itm_jerky', 14, 1, 2, 'common'),
('lt_bandits_low', 'itm_torch', 10, 1, 2, 'common'),
('lt_bandits_low', 'itm_rope',  8,  1, 1, 'common'),
('lt_bandits_low', 'itm_bandage', 12, 1, 2, 'common'),
('lt_bandits_low', 'itm_coin_pouch', 6, 1, 1, 'common'),
('lt_bandits_low', 'itm_wooden_club', 8, 1, 1, 'common'),
('lt_bandits_low', 'itm_slingshot',  6, 1, 1, 'common'),

-- bandits mid
('lt_bandits_mid', 'itm_jerky',  12, 1, 2, 'common'),
('lt_bandits_mid', 'itm_torch',  10, 1, 2, 'common'),
('lt_bandits_mid', 'itm_lockpick', 7, 1, 2, 'uncommon'),
('lt_bandits_mid', 'itm_bandage', 10, 1, 3, 'common'),
('lt_bandits_mid', 'itm_iron_dagger', 7, 1, 1, 'common'),
('lt_bandits_mid', 'itm_short_bow',  5, 1, 1, 'uncommon'),
('lt_bandits_mid', 'itm_leather_helmet', 6, 1, 1, 'common'),
('lt_bandits_mid', 'itm_leather_armor',  5, 1, 1, 'common'),

-- beasts low
('lt_beasts_low',  'itm_meat',  18, 1, 2, 'common'),
('lt_beasts_low',  'itm_healing_herb', 10, 1, 1, 'common'),
('lt_beasts_low',  'itm_berry_mix', 8, 1, 1, 'common');

-- AI rules (gentle DM suggestions)
INSERT OR IGNORE INTO ai_rules (id, scope, subject_id, rule_type, priority, condition_json, effect_json, text) VALUES
('airule_bandage_low_hp', 'item', 'itm_bandage', 'suggest', 80,
 '{"hp_pct_lt":0.6}', '{"action":"use","reason":"quick heal"}',
 'Bandages help when you are hurt. If you feel wobbly, this is a great choice.'),
('airule_torch_dark_places', 'item', 'itm_torch', 'suggest', 70,
 '{"location_type_in":["cave","ruins","dungeon"]}', '{"action":"equip_or_use","reason":"light"}',
 'Torches help you see in dark places. Monsters hate surprises, but heroes love them.'),
('airule_food_after_fight', 'tag', 'item:food', 'suggest', 60,
 '{"after_encounter":1,"stamina_pct_lt":0.7}', '{"action":"eat","reason":"recover stamina"}',
 'A snack after a fight can help you recover your energy.');

/* =========================================================
   8) Optional: world_events type helpers (no schema change)
   ========================================================= */

-- Nothing required here because you already have world_events.
-- But Pack 5 expects you to log:
-- type: encounter_end, loot_generated, reputation_changed, companion_recruited, status_effect_applied


COMMIT;
