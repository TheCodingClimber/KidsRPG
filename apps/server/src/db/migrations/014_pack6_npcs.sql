PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6.2 — Schedules (NPC routines + settlement calendars)
   PACK 6.3 — Rumors (gossip propagation + truth states)
   PACK 6.4 — Relationships (friendships + reputation drift)
   ========================================================= */


/* =========================================================
   6.2) NPC SCHEDULES — templates + generated schedules
   ========================================================= */

-- A library of schedule templates by role (or building type).
-- Engine can pick one and then generate concrete npc_schedule rows.
CREATE TABLE IF NOT EXISTS npc_schedule_templates (
  id TEXT PRIMARY KEY,                -- nst_merchant_basic
  name TEXT NOT NULL,
  applies_to_role TEXT NULL,          -- merchant/guard/child/etc
  applies_to_building_type TEXT NULL, -- tavern/blacksmith/etc
  priority INTEGER NOT NULL DEFAULT 10,
  meta_json TEXT NOT NULL DEFAULT '{}' -- can store tags: {"kidSafe":true}
);

-- Each template is a list of time blocks.
-- day_of_week: 0..6 (Sun..Sat) OR -1 for "every day"
-- start_minute/end_minute: 0..1439
CREATE TABLE IF NOT EXISTS npc_schedule_template_blocks (
  template_id TEXT NOT NULL,
  day_of_week INTEGER NOT NULL DEFAULT -1,
  start_minute INTEGER NOT NULL,
  end_minute INTEGER NOT NULL,
  activity TEXT NOT NULL,             -- work/sleep/eat/patrol/play/pray/study/travel
  location_hint TEXT NOT NULL DEFAULT '', -- building / street / "near:poi_x"
  weight INTEGER NOT NULL DEFAULT 10, -- if multiple blocks overlap, choose higher weight
  meta_json TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY (template_id, day_of_week, start_minute, activity),
  FOREIGN KEY (template_id) REFERENCES npc_schedule_templates(id) ON DELETE CASCADE
);

-- Concrete schedule entries per NPC (engine-generated)
CREATE TABLE IF NOT EXISTS npc_schedules (
  id TEXT PRIMARY KEY,                -- nsch_xxx
  npc_id TEXT NOT NULL,
  day_of_week INTEGER NOT NULL,       -- 0..6
  start_minute INTEGER NOT NULL,
  end_minute INTEGER NOT NULL,
  activity TEXT NOT NULL,
  location_type TEXT NOT NULL DEFAULT 'building', -- building/settlement/poi/world
  location_id TEXT NULL,              -- building_id or poi_id etc
  note TEXT NOT NULL DEFAULT '',
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_npc_schedules_npc ON npc_schedules(npc_id);
CREATE INDEX IF NOT EXISTS idx_npc_schedules_time ON npc_schedules(day_of_week, start_minute);

-- Optional: Settlement-wide calendar events (weekly/seasonal)
CREATE TABLE IF NOT EXISTS settlement_events (
  id TEXT PRIMARY KEY,                -- sevt_brindlewick_market_day
  settlement_id TEXT NOT NULL,
  name TEXT NOT NULL,
  event_type TEXT NOT NULL,           -- market/festival/training/night_watch/church
  day_of_week INTEGER NULL,           -- weekly event if set
  start_minute INTEGER NULL,
  end_minute INTEGER NULL,
  season TEXT NULL,                   -- spring/summer/fall/winter if seasonal
  frequency TEXT NOT NULL DEFAULT 'weekly', -- weekly/seasonal/oneoff
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_settlement_events_settlement ON settlement_events(settlement_id);

-- Seed schedule templates (kid-safe, high activity density)
INSERT OR IGNORE INTO npc_schedule_templates (id, name, applies_to_role, applies_to_building_type, priority, meta_json) VALUES
('nst_merchant_basic',     'Merchant Basic Day',     'merchant', NULL, 20, '{"kidSafe":true}'),
('nst_blacksmith_basic',   'Blacksmith Basic Day',   'blacksmith', 'blacksmith', 20, '{"kidSafe":true}'),
('nst_alchemist_basic',    'Alchemist Basic Day',    'alchemist', 'alchemist', 20, '{"kidSafe":true}'),
('nst_innkeeper_basic',    'Innkeeper Basic Day',    'innkeeper', 'tavern', 25, '{"kidSafe":true}'),
('nst_guard_basic',        'Guard Patrol Day',       'guard', NULL, 20, '{"kidSafe":true}'),
('nst_child_basic',        'Child Play & Learn',     'child', NULL, 30, '{"kidSafe":true}'),
('nst_traveler_basic',     'Traveler Passing Through','traveler', NULL, 15, '{"kidSafe":true}'),
('nst_healer_basic',       'Healer Routine',         'healer', 'temple', 20, '{"kidSafe":true}'),
('nst_clerk_basic',        'Shop Clerk Day',         'clerk', 'general', 18, '{"kidSafe":true}');

-- Blocks for each template
-- Times are intentionally simple + readable for AI and your UI.

-- Merchant: open shop, restock, lunch, close, home
INSERT OR IGNORE INTO npc_schedule_template_blocks
(template_id, day_of_week, start_minute, end_minute, activity, location_hint, weight, meta_json) VALUES
('nst_merchant_basic', -1,  420,  480, 'morning_setup', 'building:work', 20, '{}'), -- 7:00-8:00
('nst_merchant_basic', -1,  480,  720, 'work',          'building:work', 30, '{}'), -- 8:00-12:00
('nst_merchant_basic', -1,  720,  780, 'meal',          'building:tavern_or_home', 15, '{"meal":"lunch"}'),
('nst_merchant_basic', -1,  780, 1020, 'work',          'building:work', 30, '{}'), -- 13:00-17:00
('nst_merchant_basic', -1, 1020, 1080, 'restock',       'building:work', 20, '{}'),
('nst_merchant_basic', -1, 1080, 1260, 'social',        'settlement:center', 10, '{"kidFriendly":"true"}'),
('nst_merchant_basic', -1, 1260,  420, 'sleep',         'home', 40, '{}'); -- wrap handled by engine

-- Blacksmith: forge blocks + breaks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_blacksmith_basic', -1,  420,  480, 'open_shop', 'building:work', 20, '{}'),
('nst_blacksmith_basic', -1,  480,  690, 'forge',     'building:work', 35, '{"station":"forge"}'),
('nst_blacksmith_basic', -1,  690,  750, 'meal',      'building:tavern_or_home', 15, '{"meal":"lunch"}'),
('nst_blacksmith_basic', -1,  750,  960, 'forge',     'building:work', 35, '{"station":"forge"}'),
('nst_blacksmith_basic', -1,  960, 1020, 'repair_tools','building:work', 25, '{}'),
('nst_blacksmith_basic', -1, 1020, 1140, 'trade',     'building:work', 20, '{"kidFriendly":"true"}'),
('nst_blacksmith_basic', -1, 1140, 1260, 'home_time', 'home', 10, '{}'),
('nst_blacksmith_basic', -1, 1260,  420, 'sleep',     'home', 40, '{}');

-- Alchemist: brew + gather + help
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_alchemist_basic', -1,  420,  480, 'open_shop',   'building:work', 20, '{}'),
('nst_alchemist_basic', -1,  480,  660, 'brew',        'building:work', 35, '{"station":"alchemy"}'),
('nst_alchemist_basic', -1,  660,  720, 'research',    'building:work', 25, '{}'),
('nst_alchemist_basic', -1,  720,  780, 'meal',        'building:tavern_or_home', 15, '{"meal":"lunch"}'),
('nst_alchemist_basic', -1,  780,  930, 'help_customers','building:work', 25, '{"kidFriendly":"true"}'),
('nst_alchemist_basic', -1,  930, 1020, 'gather',      'settlement:edge_or_garden', 20, '{"tags":["herb:gathering"]}'),
('nst_alchemist_basic', -1, 1020, 1140, 'brew',        'building:work', 35, '{"station":"alchemy"}'),
('nst_alchemist_basic', -1, 1140, 1260, 'home_time',   'home', 10, '{}'),
('nst_alchemist_basic', -1, 1260,  420, 'sleep',       'home', 40, '{}');

-- Innkeeper: morning prep, lunch rush, evening rush
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_innkeeper_basic', -1,  360,  480, 'kitchen_prep','building:work', 25, '{}'),
('nst_innkeeper_basic', -1,  480,  720, 'host',        'building:work', 30, '{"kidFriendly":"true"}'),
('nst_innkeeper_basic', -1,  720,  780, 'meal',        'building:work', 10, '{"meal":"lunch"}'),
('nst_innkeeper_basic', -1,  780, 1020, 'clean',       'building:work', 20, '{}'),
('nst_innkeeper_basic', -1, 1020, 1320, 'evening_rush','building:work', 35, '{"kidFriendly":"true"}'),
('nst_innkeeper_basic', -1, 1320,  360, 'sleep',       'home_or_backroom', 40, '{}');

-- Guard: patrol + posts + sleep
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_guard_basic', -1,  420,  480, 'shift_brief', 'building:guildhall_or_guardpost', 20, '{}'),
('nst_guard_basic', -1,  480,  720, 'patrol',      'settlement:roads', 30, '{"kidFriendly":"true"}'),
('nst_guard_basic', -1,  720,  780, 'meal',        'building:tavern_or_post', 15, '{"meal":"lunch"}'),
('nst_guard_basic', -1,  780, 1020, 'patrol',      'settlement:roads', 30, '{"kidFriendly":"true"}'),
('nst_guard_basic', -1, 1020, 1140, 'gate_post',   'settlement:gate', 25, '{}'),
('nst_guard_basic', -1, 1140, 1260, 'home_time',   'home', 10, '{}'),
('nst_guard_basic', -1, 1260,  420, 'sleep',       'home', 40, '{}');

-- Children: school-ish block + play blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_child_basic', -1,  480,  600, 'learn',        'settlement:common', 25, '{"kidFriendly":"true"}'),
('nst_child_basic', -1,  600,  720, 'play',         'settlement:common', 30, '{"kidFriendly":"true"}'),
('nst_child_basic', -1,  720,  780, 'meal',         'home', 20, '{"meal":"lunch"}'),
('nst_child_basic', -1,  780,  960, 'play',         'settlement:common', 30, '{"kidFriendly":"true"}'),
('nst_child_basic', -1,  960, 1080, 'chores',       'home', 15, '{"kidFriendly":"true"}'),
('nst_child_basic', -1, 1080, 1140, 'story_time',   'home', 20, '{"kidFriendly":"true"}'),
('nst_child_basic', -1, 1140,  480, 'sleep',        'home', 40, '{}');

-- Traveler: arrive, trade, rest, depart
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_traveler_basic', -1,  480,  600, 'arrive',   'settlement:road', 25, '{}'),
('nst_traveler_basic', -1,  600,  780, 'trade',    'settlement:center', 20, '{"kidFriendly":"true"}'),
('nst_traveler_basic', -1,  780,  900, 'rest',     'building:tavern', 20, '{}'),
('nst_traveler_basic', -1,  900, 1020, 'rumors',   'building:tavern', 20, '{"kidFriendly":"true"}'),
('nst_traveler_basic', -1, 1020, 1140, 'depart',   'settlement:road', 25, '{}'),
('nst_traveler_basic', -1, 1140,  480, 'camp',     'world:camp', 15, '{}');

-- Clerk: assist customers all day
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_clerk_basic', -1,  480,  720, 'assist', 'building:work', 30, '{"kidFriendly":"true"}'),
('nst_clerk_basic', -1,  720,  780, 'meal',   'building:tavern_or_home', 15, '{"meal":"lunch"}'),
('nst_clerk_basic', -1,  780, 1020, 'assist', 'building:work', 30, '{"kidFriendly":"true"}'),
('nst_clerk_basic', -1, 1020, 1140, 'clean',  'building:work', 15, '{}'),
('nst_clerk_basic', -1, 1140,  480, 'sleep',  'home', 40, '{}');

-- Seed settlement events (examples)
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, name, event_type, day_of_week, start_minute, end_minute, season, frequency, meta_json)
VALUES
('sevt_brindlewick_market', 'set_brindlewick', 'Market Morning', 'market', 6, 540, 780, NULL, 'weekly', '{"kidFriendly":true,"vendors":"many"}'),
('sevt_brindlewick_story',  'set_brindlewick', 'Story Circle',   'festival', 3, 1080, 1200, NULL, 'weekly', '{"kidFriendly":true,"theme":"heroes"}'),
('sevt_emberhold_anvil',    'set_emberhold',   'Anvil Night',    'festival', 5, 1080, 1320, NULL, 'weekly', '{"kidFriendly":true,"craftDemos":true}');


/* =========================================================
   6.3) RUMORS — definitions + instances + propagation rules
   ========================================================= */

-- What a rumor is (like a quest hook / world spice).
CREATE TABLE IF NOT EXISTS rumor_defs (
  id TEXT PRIMARY KEY,                 -- rum_ashen_summit_dragon_song
  title TEXT NOT NULL,
  text TEXT NOT NULL,                  -- kid-safe wording
  category TEXT NOT NULL DEFAULT 'mystery', -- danger/trade/mystery/help/treasure
  truth_state TEXT NOT NULL DEFAULT 'unknown', -- true/false/unknown/partial
  region_id TEXT NOT NULL DEFAULT 'hearthlands',
  settlement_id TEXT NULL,
  poi_id TEXT NULL,
  faction_id TEXT NULL,
  urgency INTEGER NOT NULL DEFAULT 20,       -- 1..100
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE SET NULL,
  FOREIGN KEY (poi_id) REFERENCES pois(id) ON DELETE SET NULL,
  FOREIGN KEY (faction_id) REFERENCES factions(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_rumor_defs_region ON rumor_defs(region_id);
CREATE INDEX IF NOT EXISTS idx_rumor_defs_settlement ON rumor_defs(settlement_id);

-- A rumor as currently circulating somewhere (who knows it, how strong it is)
CREATE TABLE IF NOT EXISTS rumor_instances (
  id TEXT PRIMARY KEY,                 -- rinst_xxx
  rumor_id TEXT NOT NULL,
  settlement_id TEXT NOT NULL,
  strength INTEGER NOT NULL DEFAULT 30, -- 0..100 (how widely known)
  freshness INTEGER NOT NULL DEFAULT 50,-- 0..100 (how recent it feels)
  last_spread_at INTEGER NOT NULL DEFAULT 0,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (rumor_id) REFERENCES rumor_defs(id) ON DELETE CASCADE,
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rumor_instances_settlement ON rumor_instances(settlement_id);

-- Rules for how rumors spread by role/activity and locations
CREATE TABLE IF NOT EXISTS rumor_spread_rules (
  id TEXT PRIMARY KEY,
  spreader_role TEXT NULL,             -- innkeeper, merchant, child, traveler, guard
  activity TEXT NULL,                  -- rumors/social/work/evening_rush/market
  location_type TEXT NULL,             -- building/settlement
  location_building_type TEXT NULL,    -- tavern/general/guildhall
  spread_chance REAL NOT NULL DEFAULT 0.25,
  boost_strength INTEGER NOT NULL DEFAULT 5,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

INSERT OR IGNORE INTO rumor_spread_rules
(id, spreader_role, activity, location_type, location_building_type, spread_chance, boost_strength, meta_json)
VALUES
('rsr_tavern_evening', 'innkeeper', 'evening_rush', 'building', 'tavern', 0.60, 12, '{"kidFriendly":true}'),
('rsr_tavern_rumors',  'traveler',  'rumors',       'building', 'tavern', 0.70, 15, '{"kidFriendly":true}'),
('rsr_market',         'merchant',  'social',       'settlement','',      0.45, 10, '{"kidFriendly":true}'),
('rsr_kids_play',      'child',     'play',         'settlement','',      0.30,  6, '{"kidFriendly":true}'),
('rsr_guard_patrol',   'guard',     'patrol',       'settlement','',      0.20,  4, '{"kidFriendly":true}');

-- Seed a few rumors (hooks, kid-safe)
INSERT OR IGNORE INTO rumor_defs
(id, title, text, category, truth_state, region_id, settlement_id, poi_id, faction_id, urgency, meta_json)
VALUES
('rum_blackbarrow_whispers', 'Whispers in Blackbarrow', 'Some say the ruins hum at dusk, like a sleepy lullaby… but nobody knows why.', 'mystery', 'unknown', 'hearthlands', 'set_brindlewick', 'poi_blackbarrow_ruins', NULL, 35, '{"kidFriendly":true}'),
('rum_mossjaw_big_tracks',   'Big Tracks near Mossjaw', 'Hunters found giant footprints that circle the cave and vanish at the river.', 'danger', 'unknown', 'hearthlands', 'set_pinehollow', 'poi_mossjaw_cave', NULL, 45, '{"kidFriendly":true}'),
('rum_emberhold_forge_song', 'The Forge That Sings', 'They swear one anvil in Emberhold rings with perfect notes when heroes are nearby.', 'mystery', 'partial', 'hearthlands', 'set_emberhold', NULL, 'faction_iron_oath', 30, '{"kidFriendly":true}'),
('rum_ashen_summit_glow',    'Glow on Ashen Summit', 'A soft green glow appears on the summit some nights—like a lantern for the sky.', 'mystery', 'unknown', 'hearthlands', 'set_cinderport', 'poi_ashen_summit', NULL, 60, '{"kidFriendly":true}');

-- Seed circulating instances
INSERT OR IGNORE INTO rumor_instances
(id, rumor_id, settlement_id, strength, freshness, last_spread_at, meta_json)
VALUES
('rinst_brindlewick_whispers','rum_blackbarrow_whispers','set_brindlewick',55,70,0,'{}'),
('rinst_pinehollow_tracks','rum_mossjaw_big_tracks','set_pinehollow',45,55,0,'{}'),
('rinst_emberhold_song','rum_emberhold_forge_song','set_emberhold',50,65,0,'{}'),
('rinst_cinderport_glow','rum_ashen_summit_glow','set_cinderport',35,50,0,'{}');


/* =========================================================
   6.4) RELATIONSHIPS — NPC<->NPC + Player reputation drift
   ========================================================= */

-- NPC relationships (friend/rival/mentor/etc) with a numeric bond
CREATE TABLE IF NOT EXISTS npc_relationships (
  id TEXT PRIMARY KEY,                 -- nrel_xxx
  npc_a_id TEXT NOT NULL,
  npc_b_id TEXT NOT NULL,
  relationship_type TEXT NOT NULL DEFAULT 'acquaintance', -- friend/rival/family/mentor/student
  bond INTEGER NOT NULL DEFAULT 0,      -- -100..+100
  trust INTEGER NOT NULL DEFAULT 0,     -- -100..+100
  last_changed_at INTEGER NOT NULL DEFAULT 0,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (npc_a_id) REFERENCES npcs(id) ON DELETE CASCADE,
  FOREIGN KEY (npc_b_id) REFERENCES npcs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_npc_relationships_a ON npc_relationships(npc_a_id);
CREATE INDEX IF NOT EXISTS idx_npc_relationships_b ON npc_relationships(npc_b_id);

-- Reputation tracking (character with factions/settlements/npcs)
CREATE TABLE IF NOT EXISTS character_reputation (
  character_id TEXT NOT NULL,
  target_type TEXT NOT NULL,           -- faction/settlement/npc
  target_id TEXT NOT NULL,
  rep INTEGER NOT NULL DEFAULT 0,       -- -100..+100
  last_changed_at INTEGER NOT NULL DEFAULT 0,
  meta_json TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY (character_id, target_type, target_id),
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_character_rep_target ON character_reputation(target_type, target_id);

-- Rules for reputation drift when events occur (engine applies these)
CREATE TABLE IF NOT EXISTS reputation_rules (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,            -- helped_npc, donated, bought_item, solved_rumor, fought_bandits
  target_type TEXT NOT NULL,           -- faction/settlement/npc
  rep_delta INTEGER NOT NULL,
  cap_min INTEGER NOT NULL DEFAULT -100,
  cap_max INTEGER NOT NULL DEFAULT 100,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

INSERT OR IGNORE INTO reputation_rules
(id, event_type, target_type, rep_delta, cap_min, cap_max, meta_json)
VALUES
('rr_help_npc','helped_npc','npc',10,-100,100,'{"kidFriendly":true}'),
('rr_help_settlement','helped_npc','settlement',5,-100,100,'{"kidFriendly":true}'),
('rr_donate_temple','donated','faction',8,-100,100,'{"factionHint":"temple","kidFriendly":true}'),
('rr_bought_goods','bought_item','settlement',1,-100,100,'{"kidFriendly":true}'),
('rr_solved_rumor','solved_rumor','settlement',6,-100,100,'{"kidFriendly":true}'),
('rr_defeat_bandits','fought_bandits','faction',10,-100,100,'{"factionHint":"wardens","kidFriendly":true}');

-- Optional: AI-friendly social facts (so the AI can narrate "these two are friends")
CREATE TABLE IF NOT EXISTS social_facts (
  id TEXT PRIMARY KEY,                -- sf_xxx
  region_id TEXT NOT NULL DEFAULT 'hearthlands',
  settlement_id TEXT NULL,
  npc_id TEXT NULL,
  fact_type TEXT NOT NULL,            -- relationship/rumor/reputation/event
  text TEXT NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE SET NULL,
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_social_facts_settlement ON social_facts(settlement_id);
CREATE INDEX IF NOT EXISTS idx_social_facts_npc ON social_facts(npc_id);


/* =========================================================
   AI-FRIENDLY VIEWS (read-only helpers)
   ========================================================= */

-- Quick NPC profile view for your AI/DM layer
CREATE VIEW IF NOT EXISTS v_npc_profile AS
SELECT
  n.id AS npc_id,
  n.name AS npc_name,
  n.role AS npc_role,
  n.settlement_id,
  s.name AS settlement_name,
  n.building_id,
  b.name AS building_name,
  b.type AS building_type,
  n.personality_tags,
  n.dialogue_seed,
  n.meta_json
FROM npcs n
LEFT JOIN settlements_v2 s ON s.id = n.settlement_id
LEFT JOIN buildings b ON b.id = n.building_id;

-- A settlement “activity summary” for AI narration
CREATE VIEW IF NOT EXISTS v_settlement_activity AS
SELECT
  s.id AS settlement_id,
  s.name AS settlement_name,
  s.type AS settlement_type,
  COUNT(DISTINCT b.id) AS business_count,
  COUNT(DISTINCT n.id) AS npc_count
FROM settlements_v2 s
LEFT JOIN buildings b ON b.settlement_id = s.id
LEFT JOIN npcs n ON n.settlement_id = s.id
GROUP BY s.id, s.name, s.type;


COMMIT;
