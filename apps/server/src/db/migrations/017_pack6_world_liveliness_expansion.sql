PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6 EXPANSION — MORE NPCs + MORE RUMORS + MORE EVENTS
   Assumes Pack 6.2/6.3/6.4 tables already exist.
   Safe to re-run (INSERT OR IGNORE).
   ========================================================= */

------------------------------------------------------------
-- 1) MORE SCHEDULE TEMPLATES (more role variety)
------------------------------------------------------------

INSERT OR IGNORE INTO npc_schedule_templates (id, name, applies_to_role, applies_to_building_type, priority, meta_json) VALUES
('nst_bard_basic',          'Bard: Practice + Perform',        'bard',        'tavern',    22, '{"kidSafe":true,"tags":["music","social"]}'),
('nst_farmer_basic',        'Farmer: Dawn Fields',             'farmer',      NULL,       18, '{"kidSafe":true,"tags":["outdoors","routine"]}'),
('nst_fisher_basic',        'Fisher: Nets + Market',           'fisher',      NULL,       18, '{"kidSafe":true,"tags":["water","trade"]}'),
('nst_priest_basic',        'Priest: Services + Counseling',   'priest',      'temple',    22, '{"kidSafe":true,"tags":["helpful","calm"]}'),
('nst_scribe_basic',        'Scribe: Records + Notices',       'scribe',      NULL,       16, '{"kidSafe":true,"tags":["paperwork","rumors"]}'),
('nst_trainer_basic',       'Trainer: Yard + Sparring',        'trainer',     NULL,       20, '{"kidSafe":true,"tags":["training","discipline"]}'),
('nst_street_vendor_basic', 'Street Vendor: Roam + Sell',      'vendor',      NULL,       19, '{"kidSafe":true,"tags":["market","wandering"]}'),
('nst_librarian_basic',     'Librarian: Quiet Hours',          'librarian',   NULL,       16, '{"kidSafe":true,"tags":["books","calm"]}'),
('nst_carpenter_basic',     'Carpenter: Build + Repair',       'carpenter',   'workshop',  19, '{"kidSafe":true,"tags":["crafting","workbench"]}'),
('nst_stablehand_basic',    'Stablehand: Feed + Groom',        'stablehand',  'stables',   18, '{"kidSafe":true,"tags":["animals","care"]}');

-- Bard blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks
(template_id, day_of_week, start_minute, end_minute, activity, location_hint, weight, meta_json) VALUES
('nst_bard_basic', -1,  540,  660, 'practice',     'building:work', 20, '{"kidFriendly":true}'),   -- 9:00-11:00
('nst_bard_basic', -1,  660,  720, 'social',       'settlement:center', 15, '{"kidFriendly":true}'),
('nst_bard_basic', -1,  720,  780, 'meal',         'building:work', 10, '{"meal":"lunch"}'),
('nst_bard_basic', -1,  780,  960, 'errands',      'settlement:shops', 12, '{}'),
('nst_bard_basic', -1,  960, 1080, 'rest',         'home', 10, '{}'),
('nst_bard_basic', -1, 1080, 1320, 'perform',      'building:work', 28, '{"kidFriendly":true,"primeTime":true}'),
('nst_bard_basic', -1, 1320,  540, 'sleep',        'home', 40, '{}');

-- Farmer blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_farmer_basic', -1,  300,  420, 'dawn_work',     'settlement:edge_or_fields', 22, '{}'), -- 5:00-7:00
('nst_farmer_basic', -1,  420,  660, 'fieldwork',     'settlement:edge_or_fields', 30, '{}'),
('nst_farmer_basic', -1,  660,  720, 'meal',          'home', 18, '{"meal":"breakfast_late"}'),
('nst_farmer_basic', -1,  720,  900, 'fieldwork',     'settlement:edge_or_fields', 30, '{}'),
('nst_farmer_basic', -1,  900, 1020, 'market_trip',   'settlement:center', 16, '{"kidFriendly":true}'),
('nst_farmer_basic', -1, 1020, 1140, 'home_time',     'home', 10, '{}'),
('nst_farmer_basic', -1, 1140,  300, 'sleep',         'home', 40, '{}');

-- Fisher blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_fisher_basic', -1,  360,  480, 'nets',          'settlement:waterfront', 22, '{}'),
('nst_fisher_basic', -1,  480,  690, 'fish',          'settlement:waterfront', 30, '{}'),
('nst_fisher_basic', -1,  690,  750, 'meal',          'home_or_tavern', 15, '{"meal":"lunch"}'),
('nst_fisher_basic', -1,  750,  900, 'market_sell',   'settlement:center', 20, '{"kidFriendly":true}'),
('nst_fisher_basic', -1,  900, 1020, 'repair_gear',   'home', 15, '{}'),
('nst_fisher_basic', -1, 1020, 1140, 'rumors',        'building:tavern', 12, '{"kidFriendly":true}'),
('nst_fisher_basic', -1, 1140,  360, 'sleep',         'home', 40, '{}');

-- Priest blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_priest_basic', -1,  420,  540, 'prepare',       'building:work', 18, '{}'),
('nst_priest_basic', -1,  540,  660, 'service',       'building:work', 25, '{"kidFriendly":true}'),
('nst_priest_basic', -1,  660,  720, 'counsel',       'building:work', 20, '{"kidFriendly":true}'),
('nst_priest_basic', -1,  720,  780, 'meal',          'home_or_tavern', 12, '{"meal":"lunch"}'),
('nst_priest_basic', -1,  780,  960, 'help',          'settlement:common', 16, '{"kidFriendly":true}'),
('nst_priest_basic', -1,  960, 1080, 'records',       'building:work', 10, '{}'),
('nst_priest_basic', -1, 1080, 1260, 'social',        'building:tavern_or_common', 10, '{"kidFriendly":true}'),
('nst_priest_basic', -1, 1260,  420, 'sleep',         'home', 40, '{}');

-- Scribe blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_scribe_basic', -1,  480,  660, 'records',       'settlement:center', 22, '{}'),
('nst_scribe_basic', -1,  660,  720, 'post_notices',  'settlement:center', 18, '{"kidFriendly":true}'),
('nst_scribe_basic', -1,  720,  780, 'meal',          'home_or_tavern', 12, '{"meal":"lunch"}'),
('nst_scribe_basic', -1,  780,  960, 'records',       'settlement:center', 22, '{}'),
('nst_scribe_basic', -1,  960, 1020, 'rumors',        'building:tavern', 14, '{"kidFriendly":true}'),
('nst_scribe_basic', -1, 1020, 1140, 'home_time',     'home', 10, '{}'),
('nst_scribe_basic', -1, 1140,  480, 'sleep',         'home', 40, '{}');

-- Trainer blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_trainer_basic', -1,  480,  660, 'train_group',  'settlement:training_yard', 25, '{"kidFriendly":true}'),
('nst_trainer_basic', -1,  660,  720, 'spar',         'settlement:training_yard', 20, '{"kidFriendly":true}'),
('nst_trainer_basic', -1,  720,  780, 'meal',         'home_or_tavern', 12, '{"meal":"lunch"}'),
('nst_trainer_basic', -1,  780,  960, 'train_group',  'settlement:training_yard', 25, '{"kidFriendly":true}'),
('nst_trainer_basic', -1,  960, 1080, 'coach',        'building:tavern_or_common', 12, '{"kidFriendly":true}'),
('nst_trainer_basic', -1, 1080, 1140, 'home_time',    'home', 10, '{}'),
('nst_trainer_basic', -1, 1140,  480, 'sleep',        'home', 40, '{}');

-- Street vendor blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_street_vendor_basic', -1,  540,  660, 'set_up',     'settlement:center', 18, '{"kidFriendly":true}'),
('nst_street_vendor_basic', -1,  660,  900, 'sell',       'settlement:center', 26, '{"kidFriendly":true}'),
('nst_street_vendor_basic', -1,  900,  960, 'roam_sell',  'settlement:roads',  18, '{"kidFriendly":true}'),
('nst_street_vendor_basic', -1,  960, 1020, 'meal',       'home_or_tavern',     12, '{"meal":"late_lunch"}'),
('nst_street_vendor_basic', -1, 1020, 1140, 'sell',       'settlement:center',  22, '{"kidFriendly":true}'),
('nst_street_vendor_basic', -1, 1140, 1260, 'rumors',     'building:tavern',    12, '{"kidFriendly":true}'),
('nst_street_vendor_basic', -1, 1260,  540, 'sleep',      'home',               40, '{}');

-- Librarian blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_librarian_basic', -1,  540,  720, 'catalog',      'building:work', 22, '{}'),
('nst_librarian_basic', -1,  720,  780, 'meal',         'home_or_tavern', 12, '{"meal":"lunch"}'),
('nst_librarian_basic', -1,  780,  960, 'assist',       'building:work', 20, '{"kidFriendly":true}'),
('nst_librarian_basic', -1,  960, 1080, 'quiet_read',   'building:work', 14, '{"kidFriendly":true}'),
('nst_librarian_basic', -1, 1080, 1140, 'home_time',    'home', 10, '{}'),
('nst_librarian_basic', -1, 1140,  540, 'sleep',        'home', 40, '{}');

-- Carpenter blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_carpenter_basic', -1,  480,  660, 'build',        'building:work', 26, '{"station":"workbench"}'),
('nst_carpenter_basic', -1,  660,  720, 'errands',      'settlement:shops', 12, '{}'),
('nst_carpenter_basic', -1,  720,  780, 'meal',         'home_or_tavern', 12, '{"meal":"lunch"}'),
('nst_carpenter_basic', -1,  780,  960, 'repair',       'building:work', 22, '{"station":"workbench"}'),
('nst_carpenter_basic', -1,  960, 1080, 'help_customers','building:work', 16, '{"kidFriendly":true}'),
('nst_carpenter_basic', -1, 1080, 1140, 'home_time',    'home', 10, '{}'),
('nst_carpenter_basic', -1, 1140,  480, 'sleep',        'home', 40, '{}');

-- Stablehand blocks
INSERT OR IGNORE INTO npc_schedule_template_blocks VALUES
('nst_stablehand_basic', -1,  420,  540, 'feed',        'building:work', 22, '{"kidFriendly":true}'),
('nst_stablehand_basic', -1,  540,  660, 'groom',       'building:work', 22, '{"kidFriendly":true}'),
('nst_stablehand_basic', -1,  660,  720, 'clean',       'building:work', 18, '{}'),
('nst_stablehand_basic', -1,  720,  780, 'meal',        'home_or_tavern', 12, '{"meal":"lunch"}'),
('nst_stablehand_basic', -1,  780,  900, 'assist',      'building:work', 18, '{"kidFriendly":true}'),
('nst_stablehand_basic', -1,  900, 1020, 'errands',     'settlement:roads', 12, '{}'),
('nst_stablehand_basic', -1, 1020, 1140, 'home_time',   'home', 10, '{}'),
('nst_stablehand_basic', -1, 1140,  420, 'sleep',       'home', 40, '{}');


------------------------------------------------------------
-- 2) MORE SETTLEMENT EVENTS (weekly + seasonal flavor)
------------------------------------------------------------

-- Brindlewick: make it feel busy for a village
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, name, event_type, day_of_week, start_minute, end_minute, season, frequency, meta_json)
VALUES
('sevt_brindlewick_training_morning', 'set_brindlewick', 'Training Yard: Morning Drills', 'training', 1, 540, 660, NULL, 'weekly', '{"kidFriendly":true,"npcDensity":"high"}'),
('sevt_brindlewick_craft_swap',       'set_brindlewick', 'Craft Swap & Fix-It Hour',     'market',   2, 900, 1020, NULL, 'weekly', '{"kidFriendly":true,"theme":"repairs"}'),
('sevt_brindlewick_lantern_walk',     'set_brindlewick', 'Lantern Walk',                 'festival', 4, 1140, 1260, NULL, 'weekly', '{"kidFriendly":true,"theme":"lights"}'),
('sevt_brindlewick_scavenger',        'set_brindlewick', 'Kids Scavenger Game',          'festival', 6, 840, 930,  NULL, 'weekly', '{"kidFriendly":true,"miniQuest":true}'),
('sevt_brindlewick_warden_meet',      'set_brindlewick', 'Warden Watch Briefing',        'night_watch',0, 1080, 1140, NULL, 'weekly', '{"kidFriendly":true,"roads":"safe"}');

-- Emberhold: more craft-centered life
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, name, event_type, day_of_week, start_minute, end_minute, season, frequency, meta_json)
VALUES
('sevt_emberhold_open_forge',     'set_emberhold', 'Open Forge Demonstrations', 'festival', 2, 1080, 1260, NULL, 'weekly', '{"kidFriendly":true,"craftDemos":true}'),
('sevt_emberhold_tool_auction',   'set_emberhold', 'Tool & Trinket Auction',   'market',   4, 960, 1080,  NULL, 'weekly', '{"kidFriendly":true,"vendors":"many"}'),
('sevt_emberhold_anvil_story',    'set_emberhold', 'Anvil Stories',            'festival', 6, 1140, 1260, NULL, 'weekly', '{"kidFriendly":true,"theme":"heroes"}');

-- Cinderport: city = constant buzz
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, name, event_type, day_of_week, start_minute, end_minute, season, frequency, meta_json)
VALUES
('sevt_cinderport_docks_morning',  'set_cinderport', 'Dockside Morning Market', 'market', 1, 480, 660, NULL, 'weekly', '{"kidFriendly":true,"vendors":"tons"}'),
('sevt_cinderport_sailor_songs',   'set_cinderport', 'Sailor Songs Night',      'festival',5, 1140, 1320, NULL, 'weekly', '{"kidFriendly":true,"music":true}'),
('sevt_cinderport_notice_board',   'set_cinderport', 'Public Notices & Jobs',   'market', 3, 780, 900, NULL, 'weekly', '{"kidFriendly":true,"quests":"many"}'),
('sevt_cinderport_patrol_show',    'set_cinderport', 'Guard Parade',            'training',6, 600, 720, NULL, 'weekly', '{"kidFriendly":true,"spectacle":true}');

-- Pinehollow: forest vibes
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, name, event_type, day_of_week, start_minute, end_minute, season, frequency, meta_json)
VALUES
('sevt_pinehollow_hunters_meet',  'set_pinehollow', 'Hunters Meet-Up',        'market',   2, 1020, 1140, NULL, 'weekly', '{"kidFriendly":true,"theme":"tracks"}'),
('sevt_pinehollow_story_stump',   'set_pinehollow', 'Story Stump Circle',     'festival', 4, 1080, 1200, NULL, 'weekly', '{"kidFriendly":true,"theme":"mystery"}'),
('sevt_pinehollow_herb_walk',     'set_pinehollow', 'Herb Walk',              'festival', 6, 540, 660,  NULL, 'weekly', '{"kidFriendly":true,"alchemy":true}');

-- Stoneford: warden-ish town
INSERT OR IGNORE INTO settlement_events
(id, settlement_id, name, event_type, day_of_week, start_minute, end_minute, season, frequency, meta_json)
VALUES
('sevt_stoneford_road_brief',  'set_stoneford', 'Road Safety Briefing', 'night_watch', 1, 1020, 1080, NULL, 'weekly', '{"kidFriendly":true,"roads":"safer"}'),
('sevt_stoneford_training',    'set_stoneford', 'Sparring Night',       'training',    3, 1140, 1260, NULL, 'weekly', '{"kidFriendly":true,"spectators":true}'),
('sevt_stoneford_bounty_hour', 'set_stoneford', 'Bounty Hour',          'market',      5, 780, 900,   NULL, 'weekly', '{"kidFriendly":true,"quests":"bounties"}');


------------------------------------------------------------
-- 3) MORE BUILDINGS (more businesses = more NPC anchors)
------------------------------------------------------------

-- Brindlewick (village) — make it feel packed but believable
INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id, meta_json) VALUES
('bld_brindlewick_bakery',   'set_brindlewick', 'Suncrust Bakery',         'bakery',    'campfire', NULL, '{"kidFriendly":true}'),
('bld_brindlewick_stables',  'set_brindlewick', 'Thistle Stables',         'stables',   NULL, 'faction_wardens', '{"kidFriendly":true}'),
('bld_brindlewick_temple',   'set_brindlewick', 'Hearthlight Shrine',      'temple',    NULL, NULL, '{"kidFriendly":true}'),
('bld_brindlewick_workshop', 'set_brindlewick', 'Fix-It Workshop',         'workshop',  'workbench', NULL, '{"kidFriendly":true}'),
('bld_brindlewick_library',  'set_brindlewick', 'Little Leaf Library',     'library',   NULL, NULL, '{"kidFriendly":true}');

-- Emberhold (town)
INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id, meta_json) VALUES
('bld_emberhold_stables',     'set_emberhold', 'Cinder Stables',          'stables',   NULL, NULL, '{"kidFriendly":true}'),
('bld_emberhold_tavern',      'set_emberhold', 'The Bright Ember',        'tavern',    'campfire', NULL, '{"kidFriendly":true}'),
('bld_emberhold_library',     'set_emberhold', 'Forge-Lore Reading Hall', 'library',   NULL, 'faction_iron_oath', '{"kidFriendly":true}');

-- Cinderport (city)
INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id, meta_json) VALUES
('bld_cinderport_dock_market', 'set_cinderport', 'Dockside Market Row',  'market',   NULL, 'faction_merchants_guild', '{"kidFriendly":true,"busy":true}'),
('bld_cinderport_guildhall',   'set_cinderport', 'Merchants Hall',       'guildhall',NULL, 'faction_merchants_guild', '{"kidFriendly":true}'),
('bld_cinderport_temple',      'set_cinderport', 'Tide-Song Chapel',     'temple',   NULL, NULL, '{"kidFriendly":true}'),
('bld_cinderport_tavern',      'set_cinderport', 'The Brass Anchor',     'tavern',   'campfire', NULL, '{"kidFriendly":true}'),
('bld_cinderport_workshop',    'set_cinderport', 'Gear & Gleam Workshop','workshop', 'workbench', NULL, '{"kidFriendly":true}');

-- Pinehollow (town)
INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id, meta_json) VALUES
('bld_pinehollow_tavern',     'set_pinehollow', 'The Pinecone Mug',     'tavern',   'campfire', NULL, '{"kidFriendly":true}'),
('bld_pinehollow_general',    'set_pinehollow', 'Hollow Goods',        'general',  NULL, NULL, '{"kidFriendly":true}'),
('bld_pinehollow_hut',        'set_pinehollow', 'Herb-Keeper Hut',     'alchemist', 'alchemy', NULL, '{"kidFriendly":true}');

-- Stoneford (town)
INSERT OR IGNORE INTO buildings (id, settlement_id, name, type, workstation, faction_id, meta_json) VALUES
('bld_stoneford_guardpost',   'set_stoneford', 'Stoneford Guardpost', 'guardpost', NULL, 'faction_wardens', '{"kidFriendly":true}'),
('bld_stoneford_tavern',      'set_stoneford', 'The Stone Ladle',     'tavern',     'campfire', NULL, '{"kidFriendly":true}'),
('bld_stoneford_training',    'set_stoneford', 'Wardens Training Yard','training_yard', NULL, 'faction_wardens', '{"kidFriendly":true}');


------------------------------------------------------------
-- 4) MORE NPCs (busy towns need faces; give AI lots to roleplay)
------------------------------------------------------------

-- Brindlewick NPCs
INSERT OR IGNORE INTO npcs
(id, settlement_id, building_id, name, role, personality_tags, dialogue_seed, schedule_json, meta_json)
VALUES
('npc_brw_baker_tessa', 'set_brindlewick', 'bld_brindlewick_bakery', 'Tessa Suncrust', 'baker',
 '["cheerful","organized","feeds_everyone"]',
 'Hands out warm bread and warmer advice. Knows who visits town hungry.',
 '{}', '{"scheduleTemplate":"nst_merchant_basic","kidFriendly":true}'),

('npc_brw_priest_arden', 'set_brindlewick', 'bld_brindlewick_temple', 'Arden Hearthlight', 'priest',
 '["calm","patient","hopeful"]',
 'Listens like your words matter. Offers gentle quests that help people.',
 '{}', '{"scheduleTemplate":"nst_priest_basic","kidFriendly":true}'),

('npc_brw_librarian_mina', 'set_brindlewick', 'bld_brindlewick_library', 'Mina Leafwell', 'librarian',
 '["quiet","observant","secretly_funny"]',
 'Keeps stories, maps, and the “lost & found” shelf. Notices patterns in rumors.',
 '{}', '{"scheduleTemplate":"nst_librarian_basic","kidFriendly":true}'),

('npc_brw_stablehand_rook', 'set_brindlewick', 'bld_brindlewick_stables', 'Rook Thistle', 'stablehand',
 '["kind_to_animals","practical","loyal"]',
 'Treats animals like people and people like… nervous animals. Helpful either way.',
 '{}', '{"scheduleTemplate":"nst_stablehand_basic","kidFriendly":true}'),

('npc_brw_carpenter_jory', 'set_brindlewick', 'bld_brindlewick_workshop', 'Jory Fixwell', 'carpenter',
 '["tinkerer","helpful","talks_fast"]',
 'Can repair almost anything. Loves trading “one small favor” for supplies.',
 '{}', '{"scheduleTemplate":"nst_carpenter_basic","kidFriendly":true}'),

('npc_brw_bard_pip', 'set_brindlewick', 'bld_brindlewick_tavern', 'Pip Wrenstring', 'bard',
 '["dramatic","friendly","rumor_magnet"]',
 'Sings about heroes… then winks like they know a secret about you.',
 '{}', '{"scheduleTemplate":"nst_bard_basic","kidFriendly":true}'),

('npc_brw_child_ivy', 'set_brindlewick', NULL, 'Ivy Quickstep', 'child',
 '["curious","brave","truthy_liar"]',
 'Plays games that accidentally uncover real clues. Knows everyone’s shortcuts.',
 '{}', '{"scheduleTemplate":"nst_child_basic","kidFriendly":true}'),

('npc_brw_guard_sella', 'set_brindlewick', NULL, 'Sella Roadwatch', 'guard',
 '["stern","fair","protective"]',
 'Runs a tight watch but praises smart choices. Will warn you if danger rises.',
 '{}', '{"scheduleTemplate":"nst_guard_basic","kidFriendly":true}');


-- Emberhold NPCs
INSERT OR IGNORE INTO npcs
(id, settlement_id, building_id, name, role, personality_tags, dialogue_seed, schedule_json, meta_json)
VALUES
('npc_emh_bard_nix', 'set_emberhold', 'bld_emberhold_tavern', 'Nix Embernote', 'bard',
 '["warm","clever","crowd_reader"]',
 'Knows which stories calm a room and which stories start adventures.',
 '{}', '{"scheduleTemplate":"nst_bard_basic","kidFriendly":true}'),

('npc_emh_librarian_bram', 'set_emberhold', 'bld_emberhold_library', 'Bram Forge-Lore', 'librarian',
 '["serious","helpful","loves_maps"]',
 'Collects old forging blueprints and expedition journals. Hands out “research quests.”',
 '{}', '{"scheduleTemplate":"nst_librarian_basic","kidFriendly":true}'),

('npc_emh_stablehand_ki', 'set_emberhold', 'bld_emberhold_stables', 'Ki Cinderstep', 'stablehand',
 '["gentle","energetic","chatty"]',
 'Will teach kids how to calm a nervous horse. Also spreads rumors by accident.',
 '{}', '{"scheduleTemplate":"nst_stablehand_basic","kidFriendly":true}'),

('npc_emh_trainer_holt', 'set_emberhold', NULL, 'Holt Ironstride', 'trainer',
 '["disciplined","encouraging","no_nonsense"]',
 'Believes heroes are built by practice, not luck. Offers drills and small tests.',
 '{}', '{"scheduleTemplate":"nst_trainer_basic","kidFriendly":true}');


-- Cinderport NPCs
INSERT OR IGNORE INTO npcs
(id, settlement_id, building_id, name, role, personality_tags, dialogue_seed, schedule_json, meta_json)
VALUES
('npc_cdp_scribe_elo', 'set_cinderport', NULL, 'Elo Quillbright', 'scribe',
 '["busy","gossipy","kind"]',
 'Posts notices, tracks bounties, and knows which rumors are “hot today.”',
 '{}', '{"scheduleTemplate":"nst_scribe_basic","kidFriendly":true}'),

('npc_cdp_priest_maris', 'set_cinderport', 'bld_cinderport_temple', 'Maris Tide-Song', 'priest',
 '["calm","sincere","protective"]',
 'Helps travelers and offers peacekeeping quests. Has quiet authority.',
 '{}', '{"scheduleTemplate":"nst_priest_basic","kidFriendly":true}'),

('npc_cdp_vendor_zuzu', 'set_cinderport', 'bld_cinderport_dock_market', 'Zuzu Two-Bells', 'vendor',
 '["fast_talker","honest","funny"]',
 'Sells trinkets and snacks. Rings two bells when “something weird” happens at the docks.',
 '{}', '{"scheduleTemplate":"nst_street_vendor_basic","kidFriendly":true}'),

('npc_cdp_bard_sable', 'set_cinderport', 'bld_cinderport_tavern', 'Sable Brasschorus', 'bard',
 '["charming","mischievous","observant"]',
 'Can turn any rumor into a song. Sometimes songs become… clues.',
 '{}', '{"scheduleTemplate":"nst_bard_basic","kidFriendly":true}'),

('npc_cdp_guard_vann', 'set_cinderport', NULL, 'Vann Dockwarden', 'guard',
 '["stern","proud","fair"]',
 'Keeps peace at the busiest place in the region. Rewards helpers with trust.',
 '{}', '{"scheduleTemplate":"nst_guard_basic","kidFriendly":true}'),

('npc_cdp_carpenter_gem', 'set_cinderport', 'bld_cinderport_workshop', 'Gem Gearwright', 'carpenter',
 '["inventive","friendly","patient_teacher"]',
 'Builds gadgets and repairs tools. Offers “build a thing” mini-quests.',
 '{}', '{"scheduleTemplate":"nst_carpenter_basic","kidFriendly":true}');


-- Pinehollow NPCs
INSERT OR IGNORE INTO npcs
(id, settlement_id, building_id, name, role, personality_tags, dialogue_seed, schedule_json, meta_json)
VALUES
('npc_pnh_farmer_yuna', 'set_pinehollow', NULL, 'Yuna Mossfield', 'farmer',
 '["hardworking","warm","forestwise"]',
 'Grows food near the woods and knows which trails are safe.',
 '{}', '{"scheduleTemplate":"nst_farmer_basic","kidFriendly":true}'),

('npc_pnh_fisher_tarn', 'set_pinehollow', NULL, 'Tarn Reedline', 'fisher',
 '["quiet","brave","patient"]',
 'Brings in river fish and listens more than they speak. Notices tracks.',
 '{}', '{"scheduleTemplate":"nst_fisher_basic","kidFriendly":true}'),

('npc_pnh_alch_fenn', 'set_pinehollow', 'bld_pinehollow_hut', 'Fenn Herbalook', 'alchemist',
 '["quirky","helpful","curious"]',
 'Trades small potions for interesting herbs and fun stories.',
 '{}', '{"scheduleTemplate":"nst_alchemist_basic","kidFriendly":true}'),

('npc_pnh_merchant_ria', 'set_pinehollow', 'bld_pinehollow_general', 'Ria Hollowgoods', 'merchant',
 '["friendly","organized","rumor_spreader"]',
 'Knows what sells and what scares people. Keeps the town informed.',
 '{}', '{"scheduleTemplate":"nst_merchant_basic","kidFriendly":true}');


-- Stoneford NPCs
INSERT OR IGNORE INTO npcs
(id, settlement_id, building_id, name, role, personality_tags, dialogue_seed, schedule_json, meta_json)
VALUES
('npc_stf_trainer_garran', 'set_stoneford', 'bld_stoneford_training', 'Garran Stoneform', 'trainer',
 '["disciplined","fair","encouraging"]',
 'Runs sparring nights and rewards preparation. Loves teaching kids simple tactics.',
 '{}', '{"scheduleTemplate":"nst_trainer_basic","kidFriendly":true}'),

('npc_stf_scribe_nell', 'set_stoneford', NULL, 'Nell Inkstep', 'scribe',
 '["focused","helpful","gossipy"]',
 'Tracks bounties and road trouble reports. Has “fresh intel.”',
 '{}', '{"scheduleTemplate":"nst_scribe_basic","kidFriendly":true}'),

('npc_stf_guard_brenn', 'set_stoneford', 'bld_stoneford_guardpost', 'Brenn Roadshield', 'guard',
 '["stern","protective","proud"]',
 'Keeps the roads safer than they have any right to be. Likes brave helpers.',
 '{}', '{"scheduleTemplate":"nst_guard_basic","kidFriendly":true}'),

('npc_stf_inn_oma', 'set_stoneford', 'bld_stoneford_tavern', 'Oma StoneLadle', 'innkeeper',
 '["motherly","sharp","protective"]',
 'Feeds people first, asks questions second. Collects rumors like recipes.',
 '{}', '{"scheduleTemplate":"nst_innkeeper_basic","kidFriendly":true}');


------------------------------------------------------------
-- 5) MORE RUMORS (make the “conversation engine” feel endless)
------------------------------------------------------------

-- A bigger rumor spread rule set so it’s not always taverns
INSERT OR IGNORE INTO rumor_spread_rules
(id, spreader_role, activity, location_type, location_building_type, spread_chance, boost_strength, meta_json)
VALUES
('rsr_library_whispers', 'librarian', 'assist', 'building', 'library', 0.25, 6, '{"kidFriendly":true}'),
('rsr_training_yard',    'trainer',   'train_group', 'settlement', '', 0.30, 7, '{"kidFriendly":true}'),
('rsr_bakery_line',      'baker',     'work', 'building', 'bakery', 0.28, 6, '{"kidFriendly":true}'),
('rsr_market_vendor',    'vendor',    'sell', 'settlement', '', 0.42, 9, '{"kidFriendly":true}'),
('rsr_temple_help',      'priest',    'help', 'settlement', '', 0.20, 5, '{"kidFriendly":true}'),
('rsr_scribe_notices',   'scribe',    'post_notices', 'settlement', '', 0.35, 8, '{"kidFriendly":true}');

-- Add a bunch of rumor defs (kid-safe, varied hooks)
INSERT OR IGNORE INTO rumor_defs
(id, title, text, category, truth_state, region_id, settlement_id, poi_id, faction_id, urgency, meta_json)
VALUES
('rum_brw_bread_thief', 'The Bread Thief', 'Someone keeps taking bread at dawn—no footprints, just crumbs leading to… nowhere.', 'mystery', 'unknown', 'hearthlands', 'set_brindlewick', NULL, NULL, 25, '{"kidFriendly":true,"type":"small_mystery"}'),
('rum_brw_hidden_steps', 'Hidden Steps by the Creek', 'Kids found stone steps near the creek that weren’t there last week.', 'mystery', 'unknown', 'hearthlands', 'set_brindlewick', NULL, NULL, 35, '{"kidFriendly":true,"poiHint":"new_cache"}'),
('rum_brw_warden_whistle', 'The Warden Whistle', 'A special whistle can call help on the road—if you learn the right signal.', 'help', 'partial', 'hearthlands', 'set_brindlewick', NULL, 'faction_wardens', 30, '{"kidFriendly":true,"teaches":"signal"}'),
('rum_brw_pond_glow', 'Glow in the Pond', 'Some nights the pond sparkles like tiny stars. People argue whether it’s magic or bugs.', 'mystery', 'unknown', 'hearthlands', 'set_brindlewick', NULL, NULL, 20, '{"kidFriendly":true,"night":true}'),

('rum_emh_anvil_mood', 'The Moody Anvil', 'One anvil “sounds happy” on some days and “grumpy” on others. The smiths swear it’s real.', 'mystery', 'unknown', 'hearthlands', 'set_emberhold', NULL, 'faction_iron_oath', 25, '{"kidFriendly":true,"craftHook":true}'),
('rum_emh_missing_tongs', 'Missing Tongs', 'A set of special tongs went missing. Whoever finds them earns a tiny medal.', 'help', 'true', 'hearthlands', 'set_emberhold', NULL, NULL, 30, '{"kidFriendly":true,"miniQuest":true}'),
('rum_emh_spark_stone', 'Spark Stone', 'Miners found a stone that makes a “spark song” when tapped. Alchemists want it.', 'treasure', 'unknown', 'hearthlands', 'set_emberhold', NULL, NULL, 40, '{"kidFriendly":true,"alchemy":true}'),

('rum_cdp_dock_bells', 'Two Bells at the Docks', 'When two bells ring, something odd is happening. Some say it predicts trouble.', 'danger', 'partial', 'hearthlands', 'set_cinderport', NULL, NULL, 45, '{"kidFriendly":true,"cityFlavor":true}'),
('rum_cdp_lost_compass', 'Lost Compass of a Captain', 'A captain lost a compass that always points to “home.” People want it back.', 'help', 'unknown', 'hearthlands', 'set_cinderport', NULL, NULL, 35, '{"kidFriendly":true,"questHook":true}'),
('rum_cdp_smiling_crab', 'The Smiling Crab', 'A crab with a strange mark shows up before big waves. Sailors argue about luck.', 'mystery', 'unknown', 'hearthlands', 'set_cinderport', NULL, NULL, 25, '{"kidFriendly":true,"coastal":true}'),
('rum_cdp_guild_test', 'Merchant Guild “Tiny Test”', 'The guild sometimes tests honesty with small fake deals. Pass it, and doors open.', 'trade', 'partial', 'hearthlands', 'set_cinderport', NULL, 'faction_merchants_guild', 30, '{"kidFriendly":true,"repHook":true}'),

('rum_pnh_mossjaw_echo', 'Mossjaw Echo', 'The cave echoes differently on windy days, like it’s answering questions.', 'mystery', 'unknown', 'hearthlands', 'set_pinehollow', 'poi_mossjaw_cave', NULL, 50, '{"kidFriendly":true,"poi":"mossjaw"}'),
('rum_pnh_friendly_owl', 'Friendly Owl', 'An owl follows travelers who are “lost but kind.” It might lead to safety.', 'help', 'unknown', 'hearthlands', 'set_pinehollow', NULL, NULL, 20, '{"kidFriendly":true,"nature":true}'),
('rum_pnh_bent_trees', 'Bent Trees Trail', 'Some trees are bent like arrows pointing deeper into the woods. Who did that?', 'mystery', 'unknown', 'hearthlands', 'set_pinehollow', NULL, NULL, 35, '{"kidFriendly":true,"trail":true}'),

('rum_stf_bandit_count', 'Bandit Count Is Down', 'People say bandits are fewer lately… but that might mean they’re gathering somewhere.', 'danger', 'partial', 'hearthlands', 'set_stoneford', NULL, 'faction_wardens', 55, '{"kidFriendly":true,"bountyHook":true}'),
('rum_stf_secret_shortcut', 'A Shortcut With a Secret', 'A shortcut exists… but it only “appears” when someone whistles a tune.', 'mystery', 'unknown', 'hearthlands', 'set_stoneford', NULL, NULL, 35, '{"kidFriendly":true,"puzzle":true}');


-- Circulating instances (so each settlement has multiple active rumors)
INSERT OR IGNORE INTO rumor_instances
(id, rumor_id, settlement_id, strength, freshness, last_spread_at, meta_json)
VALUES
('rinst_brw_bread_thief',      'rum_brw_bread_thief',     'set_brindlewick', 55, 70, 0, '{}'),
('rinst_brw_hidden_steps',     'rum_brw_hidden_steps',    'set_brindlewick', 50, 60, 0, '{}'),
('rinst_brw_warden_whistle',   'rum_brw_warden_whistle',  'set_brindlewick', 40, 50, 0, '{}'),
('rinst_brw_pond_glow',        'rum_brw_pond_glow',       'set_brindlewick', 35, 65, 0, '{}'),

('rinst_emh_anvil_mood',       'rum_emh_anvil_mood',      'set_emberhold',   45, 65, 0, '{}'),
('rinst_emh_missing_tongs',    'rum_emh_missing_tongs',   'set_emberhold',   55, 60, 0, '{}'),
('rinst_emh_spark_stone',      'rum_emh_spark_stone',     'set_emberhold',   40, 55, 0, '{}'),

('rinst_cdp_dock_bells',       'rum_cdp_dock_bells',      'set_cinderport',  60, 70, 0, '{}'),
('rinst_cdp_lost_compass',     'rum_cdp_lost_compass',    'set_cinderport',  45, 60, 0, '{}'),
('rinst_cdp_smiling_crab',     'rum_cdp_smiling_crab',    'set_cinderport',  35, 50, 0, '{}'),
('rinst_cdp_guild_test',       'rum_cdp_guild_test',      'set_cinderport',  40, 55, 0, '{}'),

('rinst_pnh_mossjaw_echo',     'rum_pnh_mossjaw_echo',    'set_pinehollow',  50, 55, 0, '{}'),
('rinst_pnh_friendly_owl',     'rum_pnh_friendly_owl',    'set_pinehollow',  35, 60, 0, '{}'),
('rinst_pnh_bent_trees',       'rum_pnh_bent_trees',      'set_pinehollow',  40, 50, 0, '{}'),

('rinst_stf_bandit_count',     'rum_stf_bandit_count',    'set_stoneford',   55, 55, 0, '{}'),
('rinst_stf_secret_shortcut',  'rum_stf_secret_shortcut', 'set_stoneford',   35, 60, 0, '{}');


------------------------------------------------------------
-- 6) A FEW SOCIAL FACTS (so AI has narration “anchors”)
------------------------------------------------------------

-- Use created_at=0 for seeds; your engine can overwrite with real timestamps later.
INSERT OR IGNORE INTO social_facts
(id, region_id, settlement_id, npc_id, fact_type, text, data_json, created_at)
VALUES
('sf_brw_bard_knows_everyone', 'hearthlands', 'set_brindlewick', 'npc_brw_bard_pip', 'rumor',
 'Pip Wrenstring hears stories before they reach the job board.', '{"kidFriendly":true}', 0),

('sf_cdp_two_bells', 'hearthlands', 'set_cinderport', 'npc_cdp_vendor_zuzu', 'event',
 'Zuzu Two-Bells rings the bells when the docks get weird or busy.', '{"kidFriendly":true}', 0),

('sf_emh_open_forge', 'hearthlands', 'set_emberhold', 'npc_emh_trainer_holt', 'event',
 'Holt Ironstride hosts drills during Open Forge days to keep crowds safe.', '{"kidFriendly":true}', 0),

('sf_pnh_owl_help', 'hearthlands', 'set_pinehollow', 'npc_pnh_farmer_yuna', 'rumor',
 'Yuna Mossfield swears an owl guides kind travelers back to the road.', '{"kidFriendly":true}', 0),

('sf_stf_road_pride', 'hearthlands', 'set_stoneford', 'npc_stf_guard_brenn', 'reputation',
 'Brenn Roadshield remembers helpers and quietly makes future travel easier.', '{"kidFriendly":true}', 0);


COMMIT;
