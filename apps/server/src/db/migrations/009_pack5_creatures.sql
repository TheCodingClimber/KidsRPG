PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 5 — Encounters + Creatures (POI Danger Driven)
   - Combat style: Light tactics, narrative-first (B)
   - Defeat: KO / flee / surrender
   - Loot: always drops something
   - Scaling: by POI danger
   - Party size: up to 5
   - Befriend/recruit/rival: supported via relationship hooks
   ========================================================= */

/* =========================================================
   5.0 Tags: creature + encounter + behavior
   ========================================================= */

INSERT OR IGNORE INTO tags (id, label) VALUES
('entity:creature', 'Creature'),
('entity:npc', 'NPC'),
('encounter:bandit', 'Bandit Encounter'),
('encounter:undead', 'Undead Encounter'),
('encounter:beast', 'Beast Encounter'),
('encounter:ruins', 'Ruins Encounter'),
('encounter:road', 'Road Encounter'),
('encounter:mythic', 'Mythic Encounter'),
('behavior:fearful', 'Fearful'),
('behavior:brave', 'Brave'),
('behavior:greedy', 'Greedy'),
('behavior:loyal', 'Loyal'),
('behavior:curious', 'Curious'),
('behavior:trickster', 'Trickster'),
('behavior:protective', 'Protective'),
('behavior:pack', 'Pack Hunter'),
('behavior:boss', 'Boss-like'),
('fate:ko', 'Knockout'),
('fate:flee', 'Flee'),
('fate:surrender', 'Surrender');

/* =========================================================
   5.1 Creature definitions (kid-safe, personality-ready)
   ========================================================= */

CREATE TABLE IF NOT EXISTS creature_defs (
  id TEXT PRIMARY KEY,                 -- cr_goblin_sneak
  name TEXT NOT NULL,                  -- "Goblin Sneak"
  species TEXT NOT NULL,               -- goblin/wolf/skeleton/etc
  archetype TEXT NOT NULL DEFAULT 'minion', -- minion/brute/skirmisher/caster/boss/support
  danger_rating INTEGER NOT NULL DEFAULT 10, -- 1..100 (maps to POI danger)
  level_min INTEGER NOT NULL DEFAULT 1,
  level_max INTEGER NOT NULL DEFAULT 1,
  loot_table_id TEXT NULL,             -- fallback loot table (optional)
  meta_json TEXT NOT NULL DEFAULT '{}',-- stats/abilities/behavior/voice
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id)
);

CREATE INDEX IF NOT EXISTS idx_creature_defs_species ON creature_defs(species);
CREATE INDEX IF NOT EXISTS idx_creature_defs_danger ON creature_defs(danger_rating);

-- Creature tags (query-friendly)
CREATE TABLE IF NOT EXISTS creature_def_tags (
  creature_def_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (creature_def_id, tag_id),
  FOREIGN KEY (creature_def_id) REFERENCES creature_defs(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_creature_def_tags_tag ON creature_def_tags(tag_id);

/* =========================================================
   5.2 Encounter tables: driven by POI danger + theme
   ========================================================= */

CREATE TABLE IF NOT EXISTS encounter_tables (
  id TEXT PRIMARY KEY,                 -- ect_bandit_road_low
  name TEXT NOT NULL,
  theme TEXT NOT NULL,                 -- bandit/undead/beast/ruins/road/mythic/general
  poi_type TEXT NULL,                  -- camp/ruins/cave/summit/dungeon/shrine or NULL
  danger_min INTEGER NOT NULL DEFAULT 1,
  danger_max INTEGER NOT NULL DEFAULT 100,
  rolls INTEGER NOT NULL DEFAULT 1,     -- number of encounter "groups" to roll
  meta_json TEXT NOT NULL DEFAULT '{}'
);

-- Weighted entries: can spawn a creature_def, or an NPC faction patrol later
CREATE TABLE IF NOT EXISTS encounter_table_entries (
  id TEXT PRIMARY KEY,                 -- ete_xxx
  encounter_table_id TEXT NOT NULL,
  creature_def_id TEXT NOT NULL,
  weight INTEGER NOT NULL DEFAULT 10,
  min_count INTEGER NOT NULL DEFAULT 1,
  max_count INTEGER NOT NULL DEFAULT 3,
  rarity_bias INTEGER NOT NULL DEFAULT 0, -- -2..+2 (later: bias towards uncommon/rare variants)
  behavior_overrides_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (encounter_table_id) REFERENCES encounter_tables(id) ON DELETE CASCADE,
  FOREIGN KEY (creature_def_id) REFERENCES creature_defs(id)
);

CREATE INDEX IF NOT EXISTS idx_encounter_entries_table ON encounter_table_entries(encounter_table_id);
CREATE INDEX IF NOT EXISTS idx_encounter_entries_creature ON encounter_table_entries(creature_def_id);

-- POI → encounter profile (optional override; else use theme matching)
CREATE TABLE IF NOT EXISTS poi_encounter_profiles (
  poi_id TEXT PRIMARY KEY,
  encounter_table_id TEXT NOT NULL,
  FOREIGN KEY (poi_id) REFERENCES pois(id) ON DELETE CASCADE,
  FOREIGN KEY (encounter_table_id) REFERENCES encounter_tables(id)
);

/* =========================================================
   5.3 Runtime encounter instances (so the world can remember)
   ========================================================= */

CREATE TABLE IF NOT EXISTS encounter_instances (
  id TEXT PRIMARY KEY,                 -- enc_xxx
  region_id TEXT NOT NULL,
  poi_id TEXT NULL,
  settlement_id TEXT NULL,
  table_id TEXT NOT NULL,
  danger INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'active', -- active/resolved/escaped
  outcome TEXT NOT NULL DEFAULT 'ko',     -- ko/flee/surrender (kid-safe)
  loot_table_id TEXT NULL,               -- final loot source used
  seed INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  resolved_at INTEGER NOT NULL DEFAULT 0,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (poi_id) REFERENCES pois(id) ON DELETE SET NULL,
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE SET NULL,
  FOREIGN KEY (table_id) REFERENCES encounter_tables(id),
  FOREIGN KEY (loot_table_id) REFERENCES loot_tables(id)
);

CREATE INDEX IF NOT EXISTS idx_encounters_poi ON encounter_instances(poi_id);
CREATE INDEX IF NOT EXISTS idx_encounters_status ON encounter_instances(status);

CREATE TABLE IF NOT EXISTS encounter_participants (
  encounter_id TEXT NOT NULL,
  side TEXT NOT NULL,                   -- party/enemy/neutral
  entity_type TEXT NOT NULL,            -- character/creature/npc
  entity_id TEXT NOT NULL,              -- characters.id / creature_defs.id / npcs.id
  count INTEGER NOT NULL DEFAULT 1,      -- for creature groups
  hp_current INTEGER NOT NULL DEFAULT 0,
  hp_max INTEGER NOT NULL DEFAULT 0,
  stamina_current INTEGER NOT NULL DEFAULT 0,
  stamina_max INTEGER NOT NULL DEFAULT 0,
  state_json TEXT NOT NULL DEFAULT '{}',-- statuses: frightened, slowed, etc.
  PRIMARY KEY (encounter_id, side, entity_type, entity_id),
  FOREIGN KEY (encounter_id) REFERENCES encounter_instances(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_encounter_participants_enc ON encounter_participants(encounter_id);

/* =========================================================
   5.4 Relationships: befriend / recruit / rival scaffolding
   ========================================================= */

CREATE TABLE IF NOT EXISTS character_relationships (
  character_id TEXT NOT NULL,
  target_type TEXT NOT NULL,            -- npc/creature/faction
  target_id TEXT NOT NULL,              -- npcs.id / creature_defs.id / factions.id
  relationship TEXT NOT NULL,           -- neutral/friendly/companion/rival/hostile
  trust INTEGER NOT NULL DEFAULT 0,      -- -100..+100
  fear INTEGER NOT NULL DEFAULT 0,       -- 0..100
  respect INTEGER NOT NULL DEFAULT 0,    -- 0..100
  meta_json TEXT NOT NULL DEFAULT '{}',
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (character_id, target_type, target_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_relationships_character ON character_relationships(character_id);
CREATE INDEX IF NOT EXISTS idx_relationships_target ON character_relationships(target_type, target_id);

-- Optional: companions as “entities” (for later party UI)
CREATE TABLE IF NOT EXISTS companion_instances (
  id TEXT PRIMARY KEY,                  -- comp_xxx
  owner_character_id TEXT NOT NULL,
  source_type TEXT NOT NULL,            -- npc/creature
  source_id TEXT NOT NULL,              -- npcs.id or creature_defs.id
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'companion', -- companion/pack_mate/familiar/squire
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (owner_character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_companions_owner ON companion_instances(owner_character_id);

/* =========================================================
   5.5 SEED: Creature library (classic + mythic + humanoids)
   Stats live in meta_json for flexibility.
   Suggested meta_json keys:
     hp, stamina, armor, damage, speed
     morale (0..100), bravery (0..100), greed (0..100), curiosity (0..100), loyalty (0..100)
     tactics: ["near","far","flank","retreat_when_low"]
     talkChance (0..1), surrenderAtHpPct, fleeAtHpPct
     voice: short descriptor for AI dialogue
   ========================================================= */

INSERT OR IGNORE INTO creature_defs
(id,name,species,archetype,danger_rating,level_min,level_max,loot_table_id,meta_json)
VALUES
-- HUMANOIDS (personalities!)
('cr_bandit_scout','Bandit Scout','bandit','skirmisher',18,1,3,'loot_bandit_basic',
 '{"hp":18,"stamina":16,"armor":1,"damage":3,"speed":1,"morale":55,"greed":70,"curiosity":40,"loyalty":35,
   "tactics":["far","retreat_when_low","call_for_help"],"talkChance":0.35,"surrenderAtHpPct":0.15,"fleeAtHpPct":0.25,
   "voice":"quick-talking, a little nervous, always watching exits"}'),

('cr_bandit_bruiser','Bandit Bruiser','bandit','brute',28,2,5,'loot_bandit_basic',
 '{"hp":28,"stamina":14,"armor":2,"damage":5,"speed":0,"morale":65,"greed":60,"loyalty":55,
   "tactics":["near","protect_leader"],"talkChance":0.2,"surrenderAtHpPct":0.10,"fleeAtHpPct":0.20,
   "voice":"loud, stubborn, wants to look tough"}'),

('cr_goblin_sneak','Goblin Sneak','goblin','skirmisher',14,1,3,'loot_general_travel',
 '{"hp":14,"stamina":18,"armor":0,"damage":3,"speed":1,"morale":45,"greed":55,"curiosity":70,"trickster":80,
   "tactics":["flank","hit_and_run","retreat_when_low"],"talkChance":0.45,"surrenderAtHpPct":0.20,"fleeAtHpPct":0.30,
   "voice":"excited, sneaky, asks too many questions"}'),

('cr_goblin_boss','Goblin Boss','goblin','boss',35,3,6,'loot_ancient_ruins',
 '{"hp":36,"stamina":22,"armor":2,"damage":6,"speed":0,"morale":75,"greed":80,"loyalty":60,"bravery":55,
   "tactics":["near","order_minions","demand_surrender"],"talkChance":0.55,"surrenderAtHpPct":0.08,"fleeAtHpPct":0.12,
   "voice":"bossy, dramatic, thinks it’s a great warlord"}'),

-- BEASTS
('cr_wolf_pack','Wolf','wolf','skirmisher',16,1,4,'loot_beast_den',
 '{"hp":16,"stamina":18,"armor":1,"damage":4,"speed":1,"morale":60,"pack":90,"curiosity":30,
   "tactics":["near","pack_focus","retreat_when_low"],"talkChance":0.0,"surrenderAtHpPct":0.0,"fleeAtHpPct":0.25,
   "voice":"(animal)"}'),

('cr_boar_rager','Wild Boar','boar','brute',22,2,5,'loot_beast_den',
 '{"hp":24,"stamina":14,"armor":1,"damage":5,"speed":0,"morale":70,
   "tactics":["near","charge"],"talkChance":0.0,"surrenderAtHpPct":0.0,"fleeAtHpPct":0.15,
   "voice":"(animal)"}'),

-- UNDEAD (kid-safe “spooky”)
('cr_skeleton_rust','Rusty Skeleton','skeleton','minion',20,2,5,'loot_undead_ruins',
 '{"hp":18,"stamina":0,"armor":1,"damage":4,"speed":0,"morale":80,"fear":0,
   "tactics":["near","relentless"],"talkChance":0.05,"surrenderAtHpPct":0.0,"fleeAtHpPct":0.0,
   "voice":"clacky, echoing, oddly polite"}'),

('cr_ghost_whisper','Whispering Ghost','ghost','caster',32,3,7,'loot_undead_ruins',
 '{"hp":22,"stamina":18,"armor":0,"damage":3,"speed":1,"morale":65,"curiosity":85,
   "tactics":["far","frighten","retreat_when_low"],"talkChance":0.75,"surrenderAtHpPct":0.18,"fleeAtHpPct":0.25,
   "voice":"soft, sad, curious about the living"}'),

-- MYTHIC / WONDER
('cr_slime_bounce','Bouncy Slime','slime','minion',10,1,3,'loot_general_travel',
 '{"hp":12,"stamina":10,"armor":0,"damage":2,"speed":0,"morale":50,"curiosity":90,
   "tactics":["near","sticky"],"talkChance":0.15,"surrenderAtHpPct":0.25,"fleeAtHpPct":0.30,
   "voice":"gurgly, friendly, confused"}'),

('cr_sprite_glimmer','Glimmer Sprite','sprite','support',26,2,6,'loot_ancient_ruins',
 '{"hp":16,"stamina":22,"armor":0,"damage":2,"speed":2,"morale":55,"curiosity":95,"trickster":70,"protective":40,
   "tactics":["far","buff_allies","prank_then_peace"],"talkChance":0.9,"surrenderAtHpPct":0.22,"fleeAtHpPct":0.28,
   "voice":"fast, playful, likes riddles and dares"}'),

('cr_elemental_emberling','Emberling','elemental','caster',40,4,8,'loot_mountain_cache',
 '{"hp":26,"stamina":24,"armor":1,"damage":5,"speed":1,"morale":70,"curiosity":55,"bravery":80,
   "tactics":["far","area_spark","retreat_when_low"],"talkChance":0.35,"surrenderAtHpPct":0.12,"fleeAtHpPct":0.18,
   "voice":"crackly, proud, speaks in short poetic lines"}');

-- Creature tag links (for AI + loot + filters)
INSERT OR IGNORE INTO creature_def_tags (creature_def_id, tag_id) VALUES
('cr_bandit_scout','entity:creature'),
('cr_bandit_scout','encounter:bandit'),
('cr_bandit_scout','behavior:fearful'),
('cr_bandit_scout','behavior:greedy'),

('cr_bandit_bruiser','entity:creature'),
('cr_bandit_bruiser','encounter:bandit'),
('cr_bandit_bruiser','behavior:loyal'),

('cr_goblin_sneak','entity:creature'),
('cr_goblin_sneak','behavior:curious'),
('cr_goblin_sneak','behavior:trickster'),

('cr_goblin_boss','entity:creature'),
('cr_goblin_boss','behavior:boss'),
('cr_goblin_boss','behavior:greedy'),

('cr_wolf_pack','entity:creature'),
('cr_wolf_pack','encounter:beast'),
('cr_wolf_pack','behavior:pack'),

('cr_boar_rager','entity:creature'),
('cr_boar_rager','encounter:beast'),

('cr_skeleton_rust','entity:creature'),
('cr_skeleton_rust','encounter:undead'),
('cr_skeleton_rust','behavior:brave'),

('cr_ghost_whisper','entity:creature'),
('cr_ghost_whisper','encounter:undead'),
('cr_ghost_whisper','behavior:curious'),

('cr_slime_bounce','entity:creature'),
('cr_slime_bounce','encounter:mythic'),

('cr_sprite_glimmer','entity:creature'),
('cr_sprite_glimmer','encounter:mythic'),
('cr_sprite_glimmer','behavior:trickster'),

('cr_elemental_emberling','entity:creature'),
('cr_elemental_emberling','encounter:mythic'),
('cr_elemental_emberling','behavior:brave');

/* =========================================================
   5.6 SEED: Encounter tables (POI danger bands)
   - These are defaults; you can override per-POI via poi_encounter_profiles
   ========================================================= */

INSERT OR IGNORE INTO encounter_tables
(id,name,theme,poi_type,danger_min,danger_max,rolls,meta_json)
VALUES
('ect_road_low','Road Trouble (Low)','road',NULL,1,25,1,'{"note":"mostly small threats"}'),
('ect_road_mid','Road Trouble (Mid)','road',NULL,26,55,1,'{"note":"organized threats possible"}'),
('ect_camp_bandit','Bandit Camp','bandit','camp',15,60,2,'{"note":"bandits with personalities"}'),
('ect_cave_beast','Cave Beasts','beast','cave',10,65,2,'{"note":"packs and brutes"}'),
('ect_ruins_undead','Ruins — Spooky','undead','ruins',15,75,2,'{"note":"kid-safe spooky"}'),
('ect_ruins_ancient','Ruins — Ancient','ruins','ruins',35,95,2,'{"note":"mythic curiosities"}'),
('ect_summit_mythic','Summit — Mythic','mythic','summit',40,100,2,'{"note":"elemental energies"}');

-- Encounter entries
INSERT OR IGNORE INTO encounter_table_entries
(id,encounter_table_id,creature_def_id,weight,min_count,max_count,behavior_overrides_json)
VALUES
-- Road low
('ete_road_low_gob','ect_road_low','cr_goblin_sneak',40,1,3,'{}'),
('ete_road_low_wolf','ect_road_low','cr_wolf_pack',35,1,2,'{}'),
('ete_road_low_slime','ect_road_low','cr_slime_bounce',25,1,2,'{}'),

-- Road mid
('ete_road_mid_band_scout','ect_road_mid','cr_bandit_scout',40,1,3,'{}'),
('ete_road_mid_wolf','ect_road_mid','cr_wolf_pack',25,2,4,'{"pack":true}'),
('ete_road_mid_boar','ect_road_mid','cr_boar_rager',20,1,2,'{}'),
('ete_road_mid_sprite','ect_road_mid','cr_sprite_glimmer',15,1,1,'{"talkChance":0.95}'),

-- Bandit camp
('ete_camp_scouts','ect_camp_bandit','cr_bandit_scout',45,2,4,'{}'),
('ete_camp_bruiser','ect_camp_bandit','cr_bandit_bruiser',35,1,2,'{}'),
('ete_camp_gob','ect_camp_bandit','cr_goblin_sneak',20,1,2,'{"note":"hired troublemakers"}'),

-- Cave beasts
('ete_cave_wolves','ect_cave_beast','cr_wolf_pack',45,2,5,'{}'),
('ete_cave_boar','ect_cave_beast','cr_boar_rager',30,1,2,'{}'),
('ete_cave_slime','ect_cave_beast','cr_slime_bounce',25,1,3,'{}'),

-- Ruins undead
('ete_ruins_skel','ect_ruins_undead','cr_skeleton_rust',55,2,5,'{}'),
('ete_ruins_ghost','ect_ruins_undead','cr_ghost_whisper',45,1,2,'{"talkChance":0.85}'),

-- Ruins ancient
('ete_ruins_sprite','ect_ruins_ancient','cr_sprite_glimmer',55,1,2,'{"talkChance":0.95}'),
('ete_ruins_gob_boss','ect_ruins_ancient','cr_goblin_boss',25,1,1,'{}'),
('ete_ruins_ghost','ect_ruins_ancient','cr_ghost_whisper',20,1,1,'{"talkChance":0.9}'),

-- Summit mythic
('ete_summit_ember','ect_summit_mythic','cr_elemental_emberling',70,1,2,'{}'),
('ete_summit_sprite','ect_summit_mythic','cr_sprite_glimmer',30,1,2,'{"note":"curious observers"}');

/* =========================================================
   5.7 POI overrides (tie your existing POIs to encounter tables)
   ========================================================= */

-- If you want exact matching by POI, do it here:
INSERT OR IGNORE INTO poi_encounter_profiles (poi_id, encounter_table_id) VALUES
('poi_roadside_bandits','ect_camp_bandit'),
('poi_sablecliff_camp','ect_camp_bandit'),
('poi_mossjaw_cave','ect_cave_beast'),
('poi_blackbarrow_ruins','ect_ruins_undead'),
('poi_ashen_summit','ect_summit_mythic');

/* =========================================================
   5.8 AI-friendly views for reasoning
   ========================================================= */

-- What encounter table applies to a POI (override first; else infer by poi.type)
CREATE VIEW IF NOT EXISTS v_poi_encounter_table AS
SELECT
  p.id AS poi_id,
  p.name AS poi_name,
  p.type AS poi_type,
  p.danger,
  COALESCE(pep.encounter_table_id,
    CASE
      WHEN p.type = 'camp' THEN 'ect_camp_bandit'
      WHEN p.type = 'cave' THEN 'ect_cave_beast'
      WHEN p.type = 'ruins' THEN 'ect_ruins_undead'
      WHEN p.type = 'summit' THEN 'ect_summit_mythic'
      ELSE
        CASE
          WHEN p.danger <= 25 THEN 'ect_road_low'
          WHEN p.danger <= 55 THEN 'ect_road_mid'
          ELSE 'ect_road_mid'
        END
    END
  ) AS encounter_table_id
FROM pois p
LEFT JOIN poi_encounter_profiles pep ON pep.poi_id = p.id;

-- Creature profile for AI dialogue + decisions
CREATE VIEW IF NOT EXISTS v_creature_profile AS
SELECT
  c.id AS creature_def_id,
  c.name,
  c.species,
  c.archetype,
  c.danger_rating,
  c.loot_table_id,
  json_extract(c.meta_json,'$.hp') AS hp,
  json_extract(c.meta_json,'$.stamina') AS stamina,
  json_extract(c.meta_json,'$.armor') AS armor,
  json_extract(c.meta_json,'$.damage') AS damage,
  json_extract(c.meta_json,'$.speed') AS speed,
  json_extract(c.meta_json,'$.morale') AS morale,
  json_extract(c.meta_json,'$.greed') AS greed,
  json_extract(c.meta_json,'$.curiosity') AS curiosity,
  json_extract(c.meta_json,'$.loyalty') AS loyalty,
  json_extract(c.meta_json,'$.talkChance') AS talkChance,
  json_extract(c.meta_json,'$.surrenderAtHpPct') AS surrenderAtHpPct,
  json_extract(c.meta_json,'$.fleeAtHpPct') AS fleeAtHpPct,
  json_extract(c.meta_json,'$.voice') AS voice
FROM creature_defs c;

-- Encounter table entries expanded for AI: "what might appear here?"
CREATE VIEW IF NOT EXISTS v_encounter_table_rollup AS
SELECT
  et.id AS encounter_table_id,
  et.name AS encounter_table_name,
  et.theme,
  et.poi_type,
  et.danger_min,
  et.danger_max,
  e.creature_def_id,
  cd.name AS creature_name,
  cd.species,
  cd.archetype,
  e.weight,
  e.min_count,
  e.max_count
FROM encounter_tables et
JOIN encounter_table_entries e ON e.encounter_table_id = et.id
JOIN creature_defs cd ON cd.id = e.creature_def_id;

COMMIT;
