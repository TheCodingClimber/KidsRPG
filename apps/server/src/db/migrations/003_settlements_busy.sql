PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK C: Busy Settlements (Businesses, NPCs, Schedules, Events)
   ========================================================= */

/* ---------------------------------------------------------
   1) World clock (so schedules/events can resolve "now")
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS world_time (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  day INTEGER NOT NULL DEFAULT 1,
  minute_of_day INTEGER NOT NULL DEFAULT 480, -- 0..1439 (default 8:00 AM)
  season TEXT NOT NULL DEFAULT 'spring',       -- spring/summer/fall/winter
  weather TEXT NOT NULL DEFAULT 'clear',       -- optional hook
  updated_at INTEGER NOT NULL DEFAULT 0
);

INSERT OR IGNORE INTO world_time (id) VALUES (1);


/* ---------------------------------------------------------
   2) Business templates and spawned businesses
   --------------------------------------------------------- */
-- Template = what kinds of businesses exist + rules per settlement type
CREATE TABLE IF NOT EXISTS business_templates (
  id TEXT PRIMARY KEY,                 -- bt_blacksmith
  name TEXT NOT NULL,                  -- "Blacksmith"
  building_type TEXT NOT NULL,         -- matches buildings.type
  workstation TEXT NULL,               -- forge/alchemy/workbench/campfire
  default_shop_type TEXT NULL,         -- general/blacksmith/alchemist/tavern/stables
  min_in_village INTEGER NOT NULL DEFAULT 0,
  max_in_village INTEGER NOT NULL DEFAULT 1,
  min_in_town INTEGER NOT NULL DEFAULT 0,
  max_in_town INTEGER NOT NULL DEFAULT 2,
  min_in_city INTEGER NOT NULL DEFAULT 0,
  max_in_city INTEGER NOT NULL DEFAULT 4,
  npc_roles_json TEXT NOT NULL DEFAULT '[]', -- roles expected, e.g. ["blacksmith","apprentice","merchant"]
  tags_json TEXT NOT NULL DEFAULT '[]',      -- e.g. ["trade","craft","food"]
  meta_json TEXT NOT NULL DEFAULT '{}'
);

-- Instance = one specific business in one specific settlement
CREATE TABLE IF NOT EXISTS businesses (
  id TEXT PRIMARY KEY,                 -- biz_xxx
  settlement_id TEXT NOT NULL,
  template_id TEXT NOT NULL,
  building_id TEXT NOT NULL,           -- link to buildings row (physical place)
  name TEXT NOT NULL,
  prestige INTEGER NOT NULL DEFAULT 50, -- affects stock quality, NPC pride, etc.
  open_minute INTEGER NOT NULL DEFAULT 480,  -- 8:00
  close_minute INTEGER NOT NULL DEFAULT 1200, -- 20:00
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE,
  FOREIGN KEY (template_id) REFERENCES business_templates(id) ON DELETE CASCADE,
  FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_businesses_settlement ON businesses(settlement_id);
CREATE INDEX IF NOT EXISTS idx_businesses_template ON businesses(template_id);


/* ---------------------------------------------------------
   3) NPC profiles (AI-friendly personality system)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS npc_profiles (
  npc_id TEXT PRIMARY KEY,
  age_group TEXT NOT NULL DEFAULT 'adult',     -- child/teen/adult/elder
  voice_style TEXT NOT NULL DEFAULT 'plain',   -- plain/poetic/gruff/shy/cheerful/formal
  temperament TEXT NOT NULL DEFAULT 'steady',  -- calm/steady/fiery/anxious/goofy
  morals TEXT NOT NULL DEFAULT 'neutral',      -- lawful/good/neutral/chaotic
  curiosity INTEGER NOT NULL DEFAULT 50,       -- 0..100
  kindness INTEGER NOT NULL DEFAULT 50,
  bravery INTEGER NOT NULL DEFAULT 50,
  humor INTEGER NOT NULL DEFAULT 50,
  talkativeness INTEGER NOT NULL DEFAULT 50,
  patience INTEGER NOT NULL DEFAULT 50,
  interests_json TEXT NOT NULL DEFAULT '[]',   -- ["fishing","smithing","legends"]
  dislikes_json TEXT NOT NULL DEFAULT '[]',
  secrets_json TEXT NOT NULL DEFAULT '[]',     -- hooks for quests/rumors
  faction_lean_id TEXT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE CASCADE,
  FOREIGN KEY (faction_lean_id) REFERENCES factions(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_npc_profiles_faction ON npc_profiles(faction_lean_id);


/* ---------------------------------------------------------
   4) NPC relationships (so towns feel socially "busy")
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS npc_relationships (
  a_npc_id TEXT NOT NULL,
  b_npc_id TEXT NOT NULL,
  relation TEXT NOT NULL,              -- friend/rival/family/coworker/crush/mentor
  strength INTEGER NOT NULL DEFAULT 50, -- 0..100
  notes TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (a_npc_id, b_npc_id, relation),
  FOREIGN KEY (a_npc_id) REFERENCES npcs(id) ON DELETE CASCADE,
  FOREIGN KEY (b_npc_id) REFERENCES npcs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_npc_relationships_a ON npc_relationships(a_npc_id);
CREATE INDEX IF NOT EXISTS idx_npc_relationships_b ON npc_relationships(b_npc_id);


/* ---------------------------------------------------------
   5) NPC schedules (dayparts, locations, activities)
   --------------------------------------------------------- */
-- Dayparts keep it simple and fast:
-- morning: 360..720 (6:00-12:00)
-- afternoon: 720..1080 (12:00-18:00)
-- evening: 1080..1320 (18:00-22:00)
-- night: 1320..360 (22:00-6:00) (wrap)
CREATE TABLE IF NOT EXISTS npc_schedule_rules (
  id TEXT PRIMARY KEY,                 -- nsr_xxx
  npc_id TEXT NOT NULL,
  day_of_week INTEGER NOT NULL DEFAULT 0, -- 0=everyday, 1..7 optional
  start_minute INTEGER NOT NULL,
  end_minute INTEGER NOT NULL,
  location_type TEXT NOT NULL,         -- building/poi/settlement
  location_id TEXT NOT NULL,           -- buildings.id or pois.id or settlements_v2.id
  activity TEXT NOT NULL,              -- "work","rest","drink","patrol","shop","train"
  priority INTEGER NOT NULL DEFAULT 50, -- if conflicts, higher wins
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_npc_schedule_npc ON npc_schedule_rules(npc_id);
CREATE INDEX IF NOT EXISTS idx_npc_schedule_loc ON npc_schedule_rules(location_type, location_id);


/* ---------------------------------------------------------
   6) Settlement events + calendars
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS settlement_event_templates (
  id TEXT PRIMARY KEY,                  -- et_market_day
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  default_duration_min INTEGER NOT NULL DEFAULT 240,
  default_start_minute INTEGER NOT NULL DEFAULT 600, -- 10:00
  recurrence_rule TEXT NOT NULL DEFAULT 'WEEKLY',    -- NONE/DAILY/WEEKLY/MONTHLY/SEASONAL
  crowd_level INTEGER NOT NULL DEFAULT 50,           -- 0..100
  tags_json TEXT NOT NULL DEFAULT '[]',              -- ["market","festival"]
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS settlement_events (
  id TEXT PRIMARY KEY,                  -- evt_xxx
  settlement_id TEXT NOT NULL,
  template_id TEXT NULL,                -- can be NULL for one-off events
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  day INTEGER NOT NULL,
  start_minute INTEGER NOT NULL,
  end_minute INTEGER NOT NULL,
  location_type TEXT NOT NULL DEFAULT 'settlement', -- settlement/building/poi
  location_id TEXT NOT NULL,
  is_public INTEGER NOT NULL DEFAULT 1,
  crowd_level INTEGER NOT NULL DEFAULT 50,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE,
  FOREIGN KEY (template_id) REFERENCES settlement_event_templates(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_settlement_events_settlement_day ON settlement_events(settlement_id, day);


/* ---------------------------------------------------------
   7) Seed: Business templates (lots of variety)
   --------------------------------------------------------- */
INSERT OR IGNORE INTO business_templates
(id, name, building_type, workstation, default_shop_type,
 min_in_village, max_in_village, min_in_town, max_in_town, min_in_city, max_in_city,
 npc_roles_json, tags_json, meta_json)
VALUES
('bt_general_store', 'General Store', 'general', NULL, 'general',
 1, 2, 2, 4, 3, 7,
 '["merchant","clerk","porter"]', '["trade","supplies"]', '{}'),

('bt_blacksmith', 'Blacksmith', 'blacksmith', 'forge', 'blacksmith',
 0, 1, 1, 2, 2, 4,
 '["blacksmith","apprentice","merchant"]', '["craft","metal","trade"]', '{}'),

('bt_alchemist', 'Alchemist', 'alchemist', 'alchemy', 'alchemist',
 0, 1, 1, 2, 2, 4,
 '["alchemist","herbalist","assistant"]', '["alchemy","medicine","trade"]', '{}'),

('bt_tavern', 'Tavern', 'tavern', 'campfire', 'tavern',
 1, 2, 1, 3, 2, 6,
 '["innkeeper","cook","barkeep","server"]', '["food","rumors","social"]', '{}'),

('bt_stables', 'Stables', 'stables', NULL, 'stables',
 0, 1, 1, 2, 2, 4,
 '["stablemaster","handler"]', '["travel","animals"]', '{}'),

('bt_temple', 'Temple', 'temple', NULL, NULL,
 0, 1, 1, 2, 2, 4,
 '["priest","acolyte","healer"]', '["faith","healing"]', '{}'),

('bt_guildhall', 'Guildhall', 'guildhall', NULL, NULL,
 0, 1, 1, 2, 2, 3,
 '["captain","recruiter","veteran"]', '["quests","work","bounties"]', '{}'),

('bt_market', 'Market Square', 'market', NULL, NULL,
 1, 1, 1, 1, 1, 1,
 '["vendor","performer","guard"]', '["market","festival"]', '{"is_virtual":true}'),

('bt_school', 'Schoolhouse', 'school', NULL, NULL,
 0, 1, 0, 1, 0, 2,
 '["teacher","child"]', '["learning","kids"]', '{}'),

('bt_fisher', 'Fishmonger', 'fishmonger', NULL, 'general',
 0, 1, 0, 2, 1, 3,
 '["fisher","merchant"]', '["food","trade"]', '{}');


/* ---------------------------------------------------------
   8) Seed: Event templates (so every settlement has a rhythm)
   --------------------------------------------------------- */
INSERT OR IGNORE INTO settlement_event_templates
(id, name, description, default_duration_min, default_start_minute, recurrence_rule, crowd_level, tags_json, meta_json)
VALUES
('et_market_day', 'Market Day', 'Vendors set up stalls, gossip flows, kids run wild.', 360, 540, 'WEEKLY', 75, '["market","trade","social"]', '{}'),
('et_training_night', 'Training Night', 'Locals spar and practice in friendly competition.', 180, 1080, 'WEEKLY', 55, '["combat","social"]', '{}'),
('et_story_circle', 'Story Circle', 'A cozy evening of legends, songs, and rumors.', 120, 1140, 'WEEKLY', 45, '["rumors","social"]', '{}'),
('et_festival_small', 'Small Festival', 'A local celebration with food, games, and prizes.', 480, 600, 'SEASONAL', 85, '["festival","games"]', '{}');


/* ---------------------------------------------------------
   9) Seed: Add “busy” businesses to Hearthlands settlements
   ---------------------------------------------------------
   We’ll spawn several businesses per settlement manually (seed),
   but your game can ALSO auto-generate more later by template rules.
   --------------------------------------------------------- */

-- Brindlewick (village) — make it feel alive
INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id, meta_json) VALUES
('bld_brindlewick_stables', 'set_brindlewick', 'Brindlewick Stables', 'stables', NULL, NULL, '{}'),
('bld_brindlewick_temple',  'set_brindlewick', 'Shrine of Hearthlight', 'temple', NULL, 'faction_wardens', '{}'),
('bld_brindlewick_market',  'set_brindlewick', 'Brindlewick Market', 'market', NULL, NULL, '{"virtual":true}');

INSERT OR IGNORE INTO businesses (id, settlement_id, template_id, building_id, name, prestige, open_minute, close_minute) VALUES
('biz_bw_general', 'set_brindlewick', 'bt_general_store', 'bld_brindlewick_general', 'Brindlewick General Goods', 52, 480, 1200),
('biz_bw_smith',   'set_brindlewick', 'bt_blacksmith',    'bld_brindlewick_smith',   'Hearth & Hammer Smithy',   60, 540, 1140),
('biz_bw_tavern',  'set_brindlewick', 'bt_tavern',        'bld_brindlewick_tavern',  'The Warm Kettle',          58, 600, 1320),
('biz_bw_stables', 'set_brindlewick', 'bt_stables',       'bld_brindlewick_stables', 'Brindlewick Stables',      45, 420, 1140),
('biz_bw_temple',  'set_brindlewick', 'bt_temple',        'bld_brindlewick_temple',  'Shrine of Hearthlight',    55, 480, 1200),
('biz_bw_market',  'set_brindlewick', 'bt_market',        'bld_brindlewick_market',  'Brindlewick Market',       50, 540, 1080);

-- Emberhold (town) — busier
INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id, meta_json) VALUES
('bld_emberhold_tavern', 'set_emberhold', 'The Cinder Cup', 'tavern', 'campfire', NULL, '{}'),
('bld_emberhold_general','set_emberhold', 'Emberhold Outfitters', 'general', NULL, 'faction_merchants_guild', '{}'),
('bld_emberhold_temple', 'set_emberhold', 'Hall of the Iron Flame', 'temple', NULL, 'faction_iron_oath', '{}'),
('bld_emberhold_market', 'set_emberhold', 'Emberhold Market', 'market', NULL, NULL, '{"virtual":true}'),
('bld_emberhold_stables','set_emberhold', 'Emberhold Stables', 'stables', NULL, NULL, '{}'),
('bld_emberhold_guild',  'set_emberhold', 'Wayfarer Guildhall', 'guildhall', NULL, 'faction_wayfarer_concord', '{}');

INSERT OR IGNORE INTO businesses (id, settlement_id, template_id, building_id, name, prestige, open_minute, close_minute) VALUES
('biz_eh_smith',   'set_emberhold', 'bt_blacksmith', 'bld_emberhold_smith',    'Emberhold Forgeworks',     70, 540, 1140),
('biz_eh_alch',    'set_emberhold', 'bt_alchemist',  'bld_emberhold_alchemy',  'Cinderleaf Alchemy',       68, 540, 1140),
('biz_eh_shop',    'set_emberhold', 'bt_general_store','bld_emberhold_general','Emberhold Outfitters',     62, 480, 1200),
('biz_eh_tavern',  'set_emberhold', 'bt_tavern',     'bld_emberhold_tavern',   'The Cinder Cup',           65, 600, 1320),
('biz_eh_temple',  'set_emberhold', 'bt_temple',     'bld_emberhold_temple',   'Hall of the Iron Flame',   60, 480, 1200),
('biz_eh_market',  'set_emberhold', 'bt_market',     'bld_emberhold_market',   'Emberhold Market',         55, 540, 1080),
('biz_eh_stables', 'set_emberhold', 'bt_stables',    'bld_emberhold_stables',  'Emberhold Stables',        55, 420, 1140),
('biz_eh_guild',   'set_emberhold', 'bt_guildhall',  'bld_emberhold_guild',    'Wayfarer Guildhall',       75, 600, 1200);


/* ---------------------------------------------------------
   10) Seed: Extra NPCs (make towns feel crowded)
   ---------------------------------------------------------
   We’re adding multiple NPCs per business + some roamers.
   You can add hundreds over time; this scaffolding supports it.
   --------------------------------------------------------- */

-- Brindlewick crowd
INSERT OR IGNORE INTO npcs (id, settlement_id, building_id, name, role, personality_tags, dialogue_seed) VALUES
('npc_bw_clerk_1','set_brindlewick','bld_brindlewick_general','Toma Reed','clerk','["helpful","fast_talker"]','Keeps the shelves neat and knows everybody’s favorite snack.'),
('npc_bw_porter_1','set_brindlewick','bld_brindlewick_general','Bram Underbough','porter','["strong","gentle"]','Carries crates like they weigh nothing. Loves jokes.'),
('npc_bw_apprentice_1','set_brindlewick','bld_brindlewick_smith','Penny Sparks','apprentice','["curious","eager","messy"]','Always has soot on her nose and big ideas.'),
('npc_bw_stable_1','set_brindlewick','bld_brindlewick_stables','Rook Hayward','stablemaster','["calm","observant"]','Understands horses better than people.'),
('npc_bw_priest_1','set_brindlewick','bld_brindlewick_temple','Sister Luma','priest','["kind","patient"]','Gives simple advice and bandages scraped knees.'),
('npc_bw_guard_1','set_brindlewick',NULL,'Warden Joss','guard','["stern","fair"]','Keeps order and knows who’s been sneaking out at night.'),
('npc_bw_kid_1','set_brindlewick',NULL,'Milo','child','["goofy","brave"]','Dares other kids to explore “haunted” places.');

INSERT OR IGNORE INTO npc_profiles
(npc_id, age_group, voice_style, temperament, morals, curiosity, kindness, bravery, humor, talkativeness, patience, interests_json, dislikes_json, secrets_json, faction_lean_id)
VALUES
('npc_bw_clerk_1','adult','cheerful','steady','good',60,70,40,65,70,55,'["snacks","rumors","maps"]','["bullies"]','["saw_strange_tracks"]','faction_merchants_guild'),
('npc_bw_porter_1','adult','plain','steady','good',40,75,55,55,50,70,'["lifting","woodworking"]','["mean_people"]','[]',NULL),
('npc_bw_apprentice_1','teen','excited','fiery','good',85,55,50,80,85,35,'["smithing","gadgets","sparks"]','["boring_work"]','["lost_a_tool_in_the_ruins"]','faction_iron_oath'),
('npc_bw_stable_1','adult','quiet','calm','neutral',55,60,45,35,30,80,'["horses","travel_stories"]','["loud_noise"]','[]',NULL),
('npc_bw_priest_1','adult','gentle','calm','good',60,85,40,40,55,90,'["healing","songs"]','["cruelty"]','["knows_old_blessing"]','faction_wardens'),
('npc_bw_guard_1','adult','formal','steady','lawful',45,55,70,25,35,75,'["patrols","justice"]','["bandits"]','["suspects_a_smuggler"]','faction_wardens'),
('npc_bw_kid_1','child','goofy','fiery','good',80,60,65,90,90,30,'["dares","treasure"]','["lectures"]','["found_a_coin_that_glows"]',NULL);

-- Emberhold crowd
INSERT OR IGNORE INTO npcs (id, settlement_id, building_id, name, role, personality_tags, dialogue_seed) VALUES
('npc_eh_barkeep_1','set_emberhold','bld_emberhold_tavern','Kara Cinderlaugh','barkeep','["funny","sharp","bold"]','Knows every regular and every secret handshake.'),
('npc_eh_guard_1','set_emberhold',NULL,'Captain Varr','guard','["disciplined","protective"]','Runs patrols like clockwork.'),
('npc_eh_vendor_1','set_emberhold','bld_emberhold_market','Old Nessa','vendor','["chatty","mysterious"]','Sells trinkets and stories—sometimes the stories bite back.'),
('npc_eh_teacher_1','set_emberhold',NULL,'Master Pell','teacher','["stern","wise"]','Teaches reading, sums, and “how not to get tricked.”');

INSERT OR IGNORE INTO npc_profiles
(npc_id, age_group, voice_style, temperament, morals, curiosity, kindness, bravery, humor, talkativeness, patience, interests_json, dislikes_json, secrets_json, faction_lean_id)
VALUES
('npc_eh_barkeep_1','adult','witty','fiery','neutral',70,55,60,90,85,45,'["rumors","games","music"]','["cheapskates"]','["heard_about_bandit_route"]',NULL),
('npc_eh_guard_1','adult','formal','steady','lawful',40,50,80,20,30,80,'["order","road_safety"]','["bandits","lies"]','["needs_help_with_case"]','faction_wardens'),
('npc_eh_vendor_1','elder','poetic','steady','neutral',75,60,45,55,85,60,'["trinkets","legends"]','["rude_people"]','["knows_hidden_cache"]',NULL),
('npc_eh_teacher_1','adult','plain','steady','good',65,65,40,25,35,85,'["history","letters","maps"]','["nonsense"]','["old_map_fragment"]',NULL);


/* ---------------------------------------------------------
   11) Schedules (so NPCs actually "live")
   --------------------------------------------------------- */

-- Brindlewick: clerk works, then tavern, then home (we’ll treat settlement as “home”)
INSERT OR IGNORE INTO npc_schedule_rules
(id, npc_id, day_of_week, start_minute, end_minute, location_type, location_id, activity, priority)
VALUES
('sch_bw_clerk_morn','npc_bw_clerk_1',0,480,720,'building','bld_brindlewick_general','work',80),
('sch_bw_clerk_aft','npc_bw_clerk_1',0,720,1080,'building','bld_brindlewick_general','work',80),
('sch_bw_clerk_eve','npc_bw_clerk_1',0,1080,1260,'building','bld_brindlewick_tavern','social',60),
('sch_bw_clerk_night','npc_bw_clerk_1',0,1260,1440,'settlement','set_brindlewick','rest',50);

-- Guard patrol blocks
INSERT OR IGNORE INTO npc_schedule_rules
(id, npc_id, day_of_week, start_minute, end_minute, location_type, location_id, activity, priority)
VALUES
('sch_bw_guard_morn','npc_bw_guard_1',0,420,780,'settlement','set_brindlewick','patrol',80),
('sch_bw_guard_aft','npc_bw_guard_1',0,780,1140,'settlement','set_brindlewick','patrol',80),
('sch_bw_guard_eve','npc_bw_guard_1',0,1140,1320,'building','bld_brindlewick_tavern','social',40),
('sch_bw_guard_night','npc_bw_guard_1',0,1320,1440,'settlement','set_brindlewick','rest',50);

-- Apprentice: smithy + tinkering at workshop (use smith)
INSERT OR IGNORE INTO npc_schedule_rules
(id, npc_id, day_of_week, start_minute, end_minute, location_type, location_id, activity, priority)
VALUES
('sch_bw_appr_work','npc_bw_apprentice_1',0,540,1080,'building','bld_brindlewick_smith','work',85),
('sch_bw_appr_eve','npc_bw_apprentice_1',0,1080,1260,'building','bld_brindlewick_tavern','social',55),
('sch_bw_appr_night','npc_bw_apprentice_1',0,1260,1440,'settlement','set_brindlewick','rest',50);

-- Kid roams + market time + bedtime
INSERT OR IGNORE INTO npc_schedule_rules
(id, npc_id, day_of_week, start_minute, end_minute, location_type, location_id, activity, priority)
VALUES
('sch_bw_kid_morn','npc_bw_kid_1',0,540,780,'building','bld_brindlewick_market','play',70),
('sch_bw_kid_aft','npc_bw_kid_1',0,780,1020,'settlement','set_brindlewick','play',70),
('sch_bw_kid_eve','npc_bw_kid_1',0,1020,1140,'building','bld_brindlewick_tavern','social',40),
('sch_bw_kid_sleep','npc_bw_kid_1',0,1140,1440,'settlement','set_brindlewick','rest',90);


/* ---------------------------------------------------------
   12) Seed: settlement events (calendar)
   --------------------------------------------------------- */
-- Brindlewick weekly rhythms (days are just numbers; your engine can map “Day 7 = Market Day”)
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, template_id, name, description, day, start_minute, end_minute, location_type, location_id, is_public, crowd_level)
VALUES
('se_bw_market_7','set_brindlewick','et_market_day','Market Day','Fresh bread, loud bargains, and a suspiciously cheap “magic” ring.',7,540,900,'building','bld_brindlewick_market',1,75),
('se_bw_story_5','set_brindlewick','et_story_circle','Story Circle','Sella hosts tales—sometimes true, sometimes dangerous.',5,1140,1260,'building','bld_brindlewick_tavern',1,45),
('se_bw_train_3','set_brindlewick','et_training_night','Training Night','Kids can spar safely and earn small prizes.',3,1080,1200,'settlement','set_brindlewick',1,55);

-- Emberhold bigger events
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, template_id, name, description, day, start_minute, end_minute, location_type, location_id, is_public, crowd_level)
VALUES
('se_eh_market_6','set_emberhold','et_market_day','Market Day','Travelers arrive; rare supplies appear; rumors spike.',6,540,930,'building','bld_emberhold_market',1,80),
('se_eh_train_2','set_emberhold','et_training_night','Forge Sparring Night','Friendly fights and crafting contests.',2,1080,1230,'building','bld_emberhold_guild',1,60);

COMMIT;
