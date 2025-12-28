PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6.5 — CROWD EFFECTS (event-driven NPC movement)
   PACK 6.6 — NOTICE BOARDS (endless micro-quests + hooks)
   ========================================================= */

------------------------------------------------------------
-- 6.5) CROWD EFFECTS
------------------------------------------------------------

-- Each event type implies a "hotspot" where crowds gather.
-- Your engine can interpret hotspot_location_type/id however you like.
-- Common patterns:
--   - location_type='building', location_id='bld_xxx'
--   - location_type='settlement', location_id='set_xxx' + meta_json {"area":"center"}
CREATE TABLE IF NOT EXISTS event_hotspots (
  id TEXT PRIMARY KEY,                  -- ehs_market, ehs_festival, ehs_training
  event_type TEXT NOT NULL,             -- market/festival/training/night_watch/...
  hotspot_location_type TEXT NOT NULL,  -- building/settlement
  hotspot_location_id TEXT NULL,        -- building_id or settlement_id
  meta_json TEXT NOT NULL DEFAULT '{}'  -- {"area":"center","radius":2}
);

-- Rules: during an active settlement_event, nudge certain NPCs toward the hotspot.
-- This does NOT force them; it provides a "crowd suggestion" your engine can apply.
CREATE TABLE IF NOT EXISTS event_crowd_rules (
  id TEXT PRIMARY KEY,                  -- ecr_market_merchants
  event_type TEXT NOT NULL,             -- market/festival/training/night_watch
  applies_to_role TEXT NULL,            -- merchant/guard/child/bard/etc
  applies_to_building_type TEXT NULL,   -- tavern/general/blacksmith/library/temple
  crowd_behavior TEXT NOT NULL,         -- attend/perform/spectate/work/security/wander
  chance REAL NOT NULL DEFAULT 0.50,    -- 0..1 chance NPC participates
  min_duration_minutes INTEGER NOT NULL DEFAULT 30,
  max_duration_minutes INTEGER NOT NULL DEFAULT 120,
  priority INTEGER NOT NULL DEFAULT 10, -- higher wins if multiple match
  meta_json TEXT NOT NULL DEFAULT '{}'  -- {"kidFriendly":true,"note":"..."}
);

-- Optional: concrete "today overrides" your engine can write (or just compute on the fly).
-- If you use this, it becomes easy to show in UI: "Town is busy: X is at Market"
CREATE TABLE IF NOT EXISTS npc_event_overrides (
  id TEXT PRIMARY KEY,                  -- neo_xxx
  npc_id TEXT NOT NULL,
  settlement_event_id TEXT NOT NULL,
  start_minute INTEGER NOT NULL,
  end_minute INTEGER NOT NULL,
  activity TEXT NOT NULL,               -- attend/perform/spectate/work/security/wander
  location_type TEXT NOT NULL,
  location_id TEXT NULL,
  reason TEXT NOT NULL DEFAULT '',
  meta_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (npc_id) REFERENCES npcs(id) ON DELETE CASCADE,
  FOREIGN KEY (settlement_event_id) REFERENCES settlement_events(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_neo_npc ON npc_event_overrides(npc_id);
CREATE INDEX IF NOT EXISTS idx_neo_event ON npc_event_overrides(settlement_event_id);
CREATE INDEX IF NOT EXISTS idx_neo_time ON npc_event_overrides(start_minute, end_minute);

-- Seed hotspots (generic defaults; you can override per settlement by inserting more rows)
INSERT OR IGNORE INTO event_hotspots
(id, event_type, hotspot_location_type, hotspot_location_id, meta_json)
VALUES
('ehs_market',     'market',     'settlement', NULL, '{"area":"center","radius":2}'),
('ehs_festival',   'festival',   'settlement', NULL, '{"area":"center","radius":3}'),
('ehs_training',   'training',   'settlement', NULL, '{"area":"training_yard","radius":2}'),
('ehs_nightwatch', 'night_watch','settlement', NULL, '{"area":"gate_or_roads","radius":2}');

-- Crowd rules: MARKET
INSERT OR IGNORE INTO event_crowd_rules
(id, event_type, applies_to_role, applies_to_building_type, crowd_behavior, chance, min_duration_minutes, max_duration_minutes, priority, meta_json)
VALUES
('ecr_market_merchants', 'market', 'merchant', NULL, 'attend', 0.85, 60, 180, 40, '{"kidFriendly":true}'),
('ecr_market_vendors',   'market', 'vendor',   NULL, 'work',   0.90, 60, 180, 45, '{"kidFriendly":true}'),
('ecr_market_children',  'market', 'child',    NULL, 'wander', 0.55, 30,  90,  20, '{"kidFriendly":true}'),
('ecr_market_bards',     'market', 'bard',     NULL, 'perform',0.45, 30,  90,  22, '{"kidFriendly":true}'),
('ecr_market_guards',    'market', 'guard',    NULL, 'security',0.50,30, 120,  25, '{"kidFriendly":true}');

-- Crowd rules: FESTIVAL / STORY / LANTERN WALK
INSERT OR IGNORE INTO event_crowd_rules
(id, event_type, applies_to_role, applies_to_building_type, crowd_behavior, chance, min_duration_minutes, max_duration_minutes, priority, meta_json)
VALUES
('ecr_festival_innkeeper','festival','innkeeper', 'tavern', 'work',     0.80, 60, 240, 40, '{"kidFriendly":true}'),
('ecr_festival_bards',    'festival','bard',     NULL,     'perform',  0.85, 45, 180, 45, '{"kidFriendly":true}'),
('ecr_festival_merchants','festival','merchant', NULL,     'attend',   0.60, 45, 180, 25, '{"kidFriendly":true}'),
('ecr_festival_children', 'festival','child',    NULL,     'spectate', 0.70, 30, 120, 25, '{"kidFriendly":true}'),
('ecr_festival_priests',  'festival','priest',   NULL,     'attend',   0.35, 30, 120, 10, '{"kidFriendly":true}'),
('ecr_festival_guards',   'festival','guard',    NULL,     'security', 0.55, 30, 180, 30, '{"kidFriendly":true}');

-- Crowd rules: TRAINING (yard gets busy)
INSERT OR IGNORE INTO event_crowd_rules
(id, event_type, applies_to_role, applies_to_building_type, crowd_behavior, chance, min_duration_minutes, max_duration_minutes, priority, meta_json)
VALUES
('ecr_training_trainers', 'training','trainer',  NULL, 'work',      0.95, 60, 180, 50, '{"kidFriendly":true}'),
('ecr_training_guards',   'training','guard',    NULL, 'spectate',  0.35, 30,  90, 15, '{"kidFriendly":true}'),
('ecr_training_children', 'training','child',    NULL, 'spectate',  0.60, 30,  90, 20, '{"kidFriendly":true}'),
('ecr_training_merchants','training','merchant', NULL, 'attend',    0.20, 30,  60,  5, '{"kidFriendly":true}');

-- Crowd rules: NIGHT WATCH / BRIEFINGS
INSERT OR IGNORE INTO event_crowd_rules
(id, event_type, applies_to_role, applies_to_building_type, crowd_behavior, chance, min_duration_minutes, max_duration_minutes, priority, meta_json)
VALUES
('ecr_watch_guards', 'night_watch','guard', NULL, 'work',     0.90, 30, 120, 50, '{"kidFriendly":true}'),
('ecr_watch_trainers','night_watch','trainer',NULL,'attend',  0.25, 30,  60, 10, '{"kidFriendly":true}'),
('ecr_watch_merchants','night_watch','merchant',NULL,'attend',0.10, 15,  45,  5, '{"kidFriendly":true}');

-- AI-friendly view: “Who is pulled into crowds today?”
CREATE VIEW IF NOT EXISTS v_event_crowd_candidates AS
SELECT
  se.id AS settlement_event_id,
  se.settlement_id,
  se.name AS event_name,
  se.event_type,
  se.day_of_week,
  se.start_minute,
  se.end_minute,
  n.id AS npc_id,
  n.name AS npc_name,
  n.role AS npc_role,
  b.type AS building_type,
  ecr.crowd_behavior,
  ecr.chance,
  ecr.priority,
  ecr.meta_json AS rule_meta
FROM settlement_events se
JOIN npcs n ON n.settlement_id = se.settlement_id
LEFT JOIN buildings b ON b.id = n.building_id
JOIN event_crowd_rules ecr
  ON ecr.event_type = se.event_type
 AND (ecr.applies_to_role IS NULL OR ecr.applies_to_role = n.role)
 AND (ecr.applies_to_building_type IS NULL OR ecr.applies_to_building_type = b.type);


------------------------------------------------------------
-- 6.6) NOTICE BOARDS (micro-quests + “always something”)
------------------------------------------------------------

-- A settlement can have one or more boards (tavern, guildhall, town square, temple).
CREATE TABLE IF NOT EXISTS notice_boards (
  id TEXT PRIMARY KEY,                  -- nb_brindlewick_square
  settlement_id TEXT NOT NULL,
  building_id TEXT NULL,
  name TEXT NOT NULL,
  board_type TEXT NOT NULL DEFAULT 'public', -- public/guild/temple/tavern
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id) REFERENCES settlements_v2(id) ON DELETE CASCADE,
  FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_notice_boards_settlement ON notice_boards(settlement_id);

-- Templates for postings. Engine can pick based on event, danger, shortages, etc.
CREATE TABLE IF NOT EXISTS notice_post_templates (
  id TEXT PRIMARY KEY,                  -- npt_missing_item
  title TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'help', -- help/trade/bounty/training/fun/mystery
  tone TEXT NOT NULL DEFAULT 'gentle',   -- gentle/neutral/firm (kid-safe firm)
  min_danger INTEGER NOT NULL DEFAULT 0,
  max_danger INTEGER NOT NULL DEFAULT 100,
  requires_event_type TEXT NULL,        -- market/festival/training/night_watch
  giver_role_hint TEXT NULL,            -- merchant/guard/innkeeper/child/priest/...
  reward_style TEXT NOT NULL DEFAULT 'small', -- small/medium/goodie/badge
  text_template TEXT NOT NULL,           -- can include {settlement} {poi} {giver} {item}
  meta_json TEXT NOT NULL DEFAULT '{}'   -- {"kidFriendly":true,"tags":["..."]}
);

-- Concrete postings visible "today"
CREATE TABLE IF NOT EXISTS notice_posts (
  id TEXT PRIMARY KEY,                  -- np_xxx
  board_id TEXT NOT NULL,
  template_id TEXT NOT NULL,
  title TEXT NOT NULL,
  text TEXT NOT NULL,
  category TEXT NOT NULL,
  tone TEXT NOT NULL,
  giver_npc_id TEXT NULL,
  poi_id TEXT NULL,
  reward_json TEXT NOT NULL DEFAULT '{}', -- {"gold":10,"items":[...],"badge":"Helper"}
  expires_at INTEGER NOT NULL DEFAULT 0,  -- unix ts; 0 means doesn't expire
  created_at INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (board_id) REFERENCES notice_boards(id) ON DELETE CASCADE,
  FOREIGN KEY (template_id) REFERENCES notice_post_templates(id) ON DELETE CASCADE,
  FOREIGN KEY (giver_npc_id) REFERENCES npcs(id) ON DELETE SET NULL,
  FOREIGN KEY (poi_id) REFERENCES pois(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_notice_posts_board ON notice_posts(board_id);
CREATE INDEX IF NOT EXISTS idx_notice_posts_category ON notice_posts(category);

-- Seed boards (public square + tavern board where applicable)
INSERT OR IGNORE INTO notice_boards (id, settlement_id, building_id, name, board_type, meta_json) VALUES
('nb_brindlewick_square', 'set_brindlewick', NULL, 'Brindlewick Public Board', 'public', '{"kidFriendly":true}'),
('nb_brindlewick_tavern', 'set_brindlewick', 'bld_brindlewick_tavern', 'Warm Kettle Board', 'tavern', '{"kidFriendly":true}'),

('nb_emberhold_square',   'set_emberhold',   NULL, 'Emberhold Public Board', 'public', '{"kidFriendly":true}'),
('nb_cinderport_square',  'set_cinderport',  NULL, 'Cinderport Public Board', 'public', '{"kidFriendly":true}'),
('nb_pinehollow_square',  'set_pinehollow',  NULL, 'Pinehollow Public Board', 'public', '{"kidFriendly":true}'),
('nb_stoneford_square',   'set_stoneford',   NULL, 'Stoneford Public Board', 'public', '{"kidFriendly":true}');

-- Seed templates (varied categories; kid-safe; “always something”)
INSERT OR IGNORE INTO notice_post_templates
(id, title, category, tone, min_danger, max_danger, requires_event_type, giver_role_hint, reward_style, text_template, meta_json)
VALUES
('npt_lost_item', 'Lost Item', 'help', 'gentle', 0, 40, NULL, 'merchant', 'small',
 '{giver} lost something important near {settlement}. If you find it, bring it back for a thank-you.',
 '{"kidFriendly":true}'),

('npt_training_challenge', 'Training Challenge', 'training', 'neutral', 0, 60, 'training', 'trainer', 'badge',
 '{giver} is hosting a friendly challenge today. Win or learn—either way, you earn respect in {settlement}.',
 '{"kidFriendly":true}'),

('npt_bounty_bandits', 'Wanted: Road Troublemakers', 'bounty', 'firm', 30, 90, NULL, 'guard', 'medium',
 'Travelers reported trouble near {poi}. Scouts needed. Be brave, be smart, and come back safe.',
 '{"kidFriendly":true,"note":"firm tone but not cruel"}'),

('npt_trade_shortage', 'Trade Shortage', 'trade', 'neutral', 0, 70, 'market', 'merchant', 'goodie',
 '{settlement} is short on {item}. Bring some to the board contact and earn a fair trade bonus.',
 '{"kidFriendly":true}'),

('npt_fun_scavenger', 'Scavenger Game!', 'fun', 'gentle', 0, 30, 'festival', 'child', 'badge',
 'A scavenger game is happening today! Find the listed silly things around {settlement} and win a small prize.',
 '{"kidFriendly":true}'),

('npt_mystery_whisper', 'Odd Mystery', 'mystery', 'neutral', 0, 80, NULL, 'librarian', 'small',
 'Someone noticed something strange: {mystery}. Curious helpers wanted (no rushing in!).',
 '{"kidFriendly":true}'),
 -- =========================================================
-- HELP (everyday town life)
-- =========================================================
('npt_help_lost_gloves', 'Lost Gloves', 'help', 'gentle', 0, 25, NULL, 'clerk', 'small',
 '{giver} lost a pair of gloves near {settlement}. If you spot them, return them for a warm thank-you.',
 '{"kidFriendly":true,"tags":["lost_and_found"]}'),

('npt_help_missing_tool', 'Missing Tool', 'help', 'neutral', 0, 35, NULL, 'blacksmith', 'small',
 '{giver} misplaced a tool needed for work. Ask around {settlement} and bring it back if found.',
 '{"kidFriendly":true,"tags":["work_help"]}'),

('npt_help_deliver_letter', 'Deliver a Letter', 'help', 'gentle', 0, 30, NULL, 'innkeeper', 'small',
 '{giver} needs a letter delivered to a friendly face in {settlement}. Quick feet, kind heart.',
 '{"kidFriendly":true,"tags":["delivery"]}'),

('npt_help_fetch_water', 'Fetch Water', 'help', 'gentle', 0, 20, NULL, 'healer', 'small',
 '{giver} asks for fresh water. Simple help can be heroic, too—bring it back clean and steady.',
 '{"kidFriendly":true,"tags":["errand"]}'),

('npt_help_find_cat', 'Find the Missing Cat', 'help', 'gentle', 0, 25, NULL, 'child', 'badge',
 'A family’s cat is missing. Listen for soft meows near {settlement}. Be gentle—cats are tiny kings.',
 '{"kidFriendly":true,"tags":["animal_friend"]}'),

('npt_help_fix_fence', 'Fix a Fence', 'help', 'neutral', 0, 40, NULL, 'farmer', 'small',
 'A fence is broken near {settlement}. Bring simple materials and patch it up to help everyone.',
 '{"kidFriendly":true,"tags":["repair","community"]}'),

('npt_help_clean_street', 'Clean-Up Crew', 'cleanup', 'gentle', 0, 25, NULL, 'guard', 'badge',
 'Join a quick clean-up in {settlement}. Sweep, tidy, and make the streets sparkle.',
 '{"kidFriendly":true,"tags":["cleanup"]}'),

('npt_help_carry_boxes', 'Carry Some Boxes', 'help', 'gentle', 0, 30, NULL, 'merchant', 'small',
 '{giver} needs help moving supplies. Strong backs earn strong smiles in {settlement}.',
 '{"kidFriendly":true,"tags":["labor_help"]}'),

-- =========================================================
-- TRADE (shortages, bargains, special requests)
-- =========================================================
('npt_trade_short_wood', 'Need: Wood Bundle', 'trade', 'neutral', 0, 60, 'market', 'merchant', 'goodie',
 '{settlement} is short on {item}. Bring some to the board contact for a fair trade bonus.',
 '{"kidFriendly":true,"tags":["shortage","material:wood"]}'),

('npt_trade_short_iron', 'Need: Iron Ore', 'trade', 'neutral', 10, 70, 'market', 'blacksmith', 'goodie',
 'The forges hunger for {item}. Bring ore to {giver} in {settlement} for a tidy reward.',
 '{"kidFriendly":true,"tags":["shortage","material:iron"]}'),

('npt_trade_short_herbs', 'Need: Apothecary Herbs', 'trade', 'gentle', 0, 65, NULL, 'alchemist', 'goodie',
 '{giver} is low on {item}. Gather carefully and bring clean bundles back to {settlement}.',
 '{"kidFriendly":true,"tags":["shortage","herb:gathering"]}'),

('npt_trade_barter_day', 'Barter Day!', 'trade', 'gentle', 0, 50, 'market', 'merchant', 'badge',
 'It’s Barter Day in {settlement}. Bring something useful and swap stories and goods.',
 '{"kidFriendly":true,"tags":["market_event"]}'),

('npt_trade_buyback_tools', 'Tool Buy-Back', 'trade', 'neutral', 0, 60, NULL, 'blacksmith', 'small',
 '{giver} will buy worn tools for parts. Bring anything you no longer need in {settlement}.',
 '{"kidFriendly":true,"tags":["recycle","repair"]}'),

('npt_trade_fair_prices', 'Fair Prices Notice', 'trade', 'firm', 0, 40, 'market', 'guard', 'small',
 'Keep trading fair in {settlement}. No pushing, no shouting, no grabbing. Kindness first.',
 '{"kidFriendly":true,"tags":["rules","market"]}'),

-- =========================================================
-- BOUNTY (kid-safe “troublemakers”, not gore)
-- =========================================================
('npt_bounty_roadside_bandits', 'Wanted: Road Troublemakers', 'bounty', 'firm', 30, 90, NULL, 'guard', 'medium',
 'Travelers reported trouble near {poi}. Scouts needed. Be brave, be smart, and come back safe.',
 '{"kidFriendly":true,"tags":["bounty","bandits"]}'),

('npt_bounty_wolf_pack', 'Wolf Pack Warning', 'bounty', 'neutral', 20, 80, NULL, 'hunter', 'medium',
 'A restless {creature} pack has been seen near {poi}. Track carefully and report back to {settlement}.',
 '{"kidFriendly":true,"tags":["bounty","beasts"]}'),

('npt_bounty_goblin_pranksters', 'Pranksters in the Hills', 'bounty', 'firm', 15, 75, NULL, 'guard', 'medium',
 'Mischief-makers keep stealing supplies near {poi}. Stop the trouble and return what’s taken.',
 '{"kidFriendly":true,"tags":["bounty","humanoids"]}'),

('npt_bounty_bridge_toll', 'False Toll at the Bridge', 'bounty', 'firm', 25, 85, NULL, 'warden', 'medium',
 'Someone set up a fake toll near {poi}. Investigate and make the road safe for families.',
 '{"kidFriendly":true,"tags":["bounty","roads"]}'),

('npt_bounty_missing_caravan', 'Missing Caravan', 'bounty', 'neutral', 35, 95, NULL, 'merchant', 'goodie',
 'A caravan is overdue from {settlement}. Check the road near {poi} and report what you find.',
 '{"kidFriendly":true,"tags":["bounty","escort"]}'),

-- =========================================================
-- TRAINING (friendly challenges, ranks, badges)
-- =========================================================
('npt_training_duel_club', 'Friendly Duel Club', 'training', 'gentle', 0, 60, 'training', 'trainer', 'badge',
 '{giver} invites you to a friendly duel lesson today in {settlement}. Practice beats panic.',
 '{"kidFriendly":true,"tags":["training","combat_safe"]}'),

('npt_training_archery_range', 'Archery Range Open', 'training', 'neutral', 0, 55, 'training', 'guard', 'badge',
 'The archery range is open in {settlement}. Keep arrows safe and aim true.',
 '{"kidFriendly":true,"tags":["training","ranged"]}'),

('npt_training_shield_wall', 'Shield Wall Drill', 'training', 'neutral', 10, 70, 'training', 'warden', 'badge',
 'Learn the shield wall. Teamwork makes heroes in {settlement}.',
 '{"kidFriendly":true,"tags":["training","party"]}'),

('npt_training_first_aid', 'First Aid Practice', 'training', 'gentle', 0, 50, NULL, 'healer', 'badge',
 '{giver} is teaching first aid basics in {settlement}. Helpful hands save the day.',
 '{"kidFriendly":true,"tags":["training","support"]}'),

-- =========================================================
-- FUN (festivals, games, contests)
-- =========================================================
('npt_fun_scavenger_hunt', 'Scavenger Hunt!', 'fun', 'gentle', 0, 30, 'festival', 'child', 'badge',
 'A scavenger hunt is happening today in {settlement}! Find silly items and win a tiny prize.',
 '{"kidFriendly":true,"tags":["festival","game"]}'),

('npt_fun_story_circle', 'Story Circle', 'fun', 'gentle', 0, 35, 'festival', 'innkeeper', 'badge',
 'Join the Story Circle in {settlement}. Tell a tale, hear a legend, earn a smile.',
 '{"kidFriendly":true,"tags":["festival","social"]}'),

('npt_fun_cookoff', 'Tiny Cook-Off', 'fun', 'neutral', 0, 40, 'festival', 'chef', 'goodie',
 'Bring an ingredient and join the cook-off in {settlement}. No flames without grown-ups nearby!',
 '{"kidFriendly":true,"tags":["festival","food"]}'),

('npt_fun_music_hour', 'Music Hour', 'fun', 'gentle', 0, 40, NULL, 'bard', 'badge',
 'Music Hour in {settlement}. Clap, sing, or just listen—good moods welcome.',
 '{"kidFriendly":true,"tags":["music","social"]}'),

-- =========================================================
-- MYSTERY (hooks without mutation; always true-to-text)
-- =========================================================
('npt_mystery_strange_light', 'Strange Light', 'mystery', 'neutral', 10, 80, NULL, 'traveler', 'small',
 'Someone saw a strange light near {poi}. Not dangerous… maybe. Investigate carefully and report back.',
 '{"kidFriendly":true,"tags":["mystery","poi_hook"]}'),

('npt_mystery_odd_sound', 'Odd Sound at Dusk', 'mystery', 'neutral', 0, 70, NULL, 'innkeeper', 'small',
 'People heard an odd sound near {poi} at dusk—like a soft song. Curious helpers wanted.',
 '{"kidFriendly":true,"tags":["mystery","rumor_adjacent"]}'),

('npt_mystery_missing_signpost', 'Missing Signpost', 'mystery', 'neutral', 0, 55, NULL, 'guard', 'small',
 'A signpost is missing near {settlement}. Find where it went and why someone moved it.',
 '{"kidFriendly":true,"tags":["mystery","roads"]}'),

('npt_mystery_secret_note', 'A Secret Note', 'mystery', 'gentle', 0, 65, NULL, 'child', 'badge',
 'A folded note was found near the board. It says: "{mystery}" — help solve it!',
 '{"kidFriendly":true,"tags":["mystery","playful"]}'),

-- =========================================================
-- EXPLORE (POI encouragement + mapping)
-- =========================================================
('npt_explore_map_sketch', 'Map Sketch Needed', 'explore', 'neutral', 10, 80, NULL, 'warden', 'medium',
 'Explorers are asked to sketch the paths near {poi}. Bring back a simple map for {settlement}.',
 '{"kidFriendly":true,"tags":["explore","mapping"]}'),

('npt_explore_safe_scout', 'Safe Scout Route', 'explore', 'gentle', 0, 45, NULL, 'guard', 'small',
 'Find a safe path between {settlement} and {poi}. Mark hazards and return with notes.',
 '{"kidFriendly":true,"tags":["explore","travel"]}'),

('npt_explore_herb_spots', 'Herb Spot Survey', 'explore', 'gentle', 0, 60, NULL, 'alchemist', 'goodie',
 'Locate good herb patches near {poi}. Don’t over-pick—leave some for tomorrow.',
 '{"kidFriendly":true,"tags":["explore","herb:gathering"]}'),

-- =========================================================
-- REPAIR (supports durability + kits)
-- =========================================================
('npt_repair_worn_gear', 'Repair Day', 'repair', 'neutral', 0, 60, NULL, 'blacksmith', 'goodie',
 '{giver} is offering repairs in {settlement}. Bring worn gear and learn how to maintain it.',
 '{"kidFriendly":true,"tags":["repair","durability"]}'),

('npt_repair_tools_needed', 'Tools Needed', 'repair', 'neutral', 0, 70, NULL, 'blacksmith', 'small',
 'The workshop needs spare parts: {item}. Bring them to {giver} in {settlement}.',
 '{"kidFriendly":true,"tags":["repair","crafting"]}'),

-- =========================================================
-- CRAFTING (station-focused hooks)
-- =========================================================
('npt_craft_workbench_demo', 'Workbench Demo', 'crafting', 'gentle', 0, 45, NULL, 'tinkerer', 'badge',
 '{giver} is showing crafting basics at the workbench in {settlement}. Beginners welcome.',
 '{"kidFriendly":true,"tags":["crafting","station:workbench"]}'),

('npt_craft_forge_demo', 'Forge Demo', 'crafting', 'neutral', 10, 65, NULL, 'blacksmith', 'badge',
 'A forge demo is happening in {settlement}. Watch sparks fly (from a safe distance).',
 '{"kidFriendly":true,"tags":["crafting","station:forge"]}'),

('npt_craft_alchemy_demo', 'Alchemy Demo', 'crafting', 'gentle', 0, 60, NULL, 'alchemist', 'badge',
 'Learn gentle mixtures in {settlement}. No scary stuff—just useful brews and smells.',
 '{"kidFriendly":true,"tags":["crafting","station:alchemy"]}'),

-- =========================================================
-- ESCORT (kid-safe: guide, watch, protect)
-- =========================================================
('npt_escort_guided_walk', 'Guided Walk', 'escort', 'gentle', 0, 55, NULL, 'warden', 'small',
 '{giver} needs helpers to guide a small group from {settlement} toward {poi}. Stay together.',
 '{"kidFriendly":true,"tags":["escort","travel_safe"]}'),

('npt_escort_caravan_watch', 'Caravan Watch', 'escort', 'neutral', 20, 85, NULL, 'merchant', 'medium',
 'A caravan needs watchful eyes along the road near {poi}. Protect goods and keep spirits up.',
 '{"kidFriendly":true,"tags":["escort","caravan"]}'),

-- =========================================================
-- FIRM TONE (still kid-safe, adds variety)
-- =========================================================
('npt_firm_rule_reminder', 'Town Rules Reminder', 'help', 'firm', 0, 40, NULL, 'guard', 'small',
 'Reminder in {settlement}: no stealing, no bullying, no pushing. Heroes protect others—even in crowds.',
 '{"kidFriendly":true,"tags":["rules","crowds"]}'),

('npt_firm_night_curfew', 'Night Curfew', 'help', 'firm', 10, 70, 'night_watch', 'guard', 'small',
 'Curfew tonight in {settlement}. Stay near lights after dark unless you’re helping official watch patrols.',
 '{"kidFriendly":true,"tags":["night_watch","safety"]}'),

-- =========================================================
-- BIG VARIETY SET (more of everything, minimal repeats)
-- =========================================================
('npt_help_bake_bread', 'Bread Help', 'help', 'gentle', 0, 35, NULL, 'chef', 'small',
 '{giver} needs help baking in {settlement}. Bring {item} and learn a simple recipe.',
 '{"kidFriendly":true,"tags":["food","campfire"]}'),

('npt_help_reading_hour', 'Reading Hour', 'fun', 'gentle', 0, 30, NULL, 'librarian', 'badge',
 'Reading Hour in {settlement}. Listen to a story and learn a new word for a tiny reward.',
 '{"kidFriendly":true,"tags":["learning","kids"]}'),

('npt_mystery_old_key', 'An Old Key', 'mystery', 'neutral', 10, 75, NULL, 'traveler', 'small',
 'Someone found an old key with no lock. Could it fit something near {poi}? Careful explorers wanted.',
 '{"kidFriendly":true,"tags":["mystery","item_hook"]}'),

('npt_explore_stone_stack', 'Stone Stack Marker', 'explore', 'neutral', 10, 70, NULL, 'warden', 'small',
 'A stone marker was stacked near {poi}. It might be a trail sign—or a warning. Investigate.',
 '{"kidFriendly":true,"tags":["explore","mystery"]}'),

('npt_bounty_pest_problem', 'Pest Problem', 'bounty', 'neutral', 10, 60, NULL, 'farmer', 'small',
 'Little troublemakers are chewing supplies near {settlement}. Help shoo them away and protect stores.',
 '{"kidFriendly":true,"tags":["bounty","nonlethal"]}'),

('npt_trade_special_request', 'Special Request', 'trade', 'neutral', 0, 80, NULL, 'merchant', 'goodie',
 '{giver} will pay extra for {item} today. Ask why—it’s a story worth hearing.',
 '{"kidFriendly":true,"tags":["trade","hook"]}'),

('npt_training_teamwork', 'Teamwork Drill', 'training', 'neutral', 0, 70, 'training', 'trainer', 'badge',
 'Practice teamwork in {settlement}. Heroes don’t win alone.',
 '{"kidFriendly":true,"tags":["training","party"]}'),

('npt_cleanup_after_market', 'After-Market Cleanup', 'cleanup', 'gentle', 0, 35, 'market', 'clerk', 'badge',
 'Market’s over—help tidy {settlement}. Clean towns feel safer.',
 '{"kidFriendly":true,"tags":["cleanup","market"]}'),

('npt_repair_boots_day', 'Boot Repair Day', 'repair', 'gentle', 0, 50, NULL, 'cobbler', 'small',
 'Worn boots slow heroes down. Bring boots to {giver} in {settlement} to patch them up.',
 '{"kidFriendly":true,"tags":["repair","movement"]}'),

('npt_crafting_supply_run', 'Supply Run for Crafting', 'crafting', 'neutral', 15, 85, NULL, 'tinkerer', 'medium',
 'Crafting needs supplies from near {poi}. Bring back {item} and learn a new trick.',
 '{"kidFriendly":true,"tags":["crafting","explore"]}'),

('npt_fun_paint_signs', 'Paint New Signs', 'fun', 'gentle', 0, 30, NULL, 'clerk', 'badge',
 'Help paint new signs in {settlement}. Bright signs help travelers and make the town cheerful.',
 '{"kidFriendly":true,"tags":["fun","town_improve"]}'),

('npt_mystery_footprints', 'Footprints That Vanish', 'mystery', 'neutral', 20, 90, NULL, 'hunter', 'small',
 'Tracks appear near {poi} and vanish at the river’s edge. Find out what’s happening.',
 '{"kidFriendly":true,"tags":["mystery","investigation"]}');

-- AI-friendly view: show boards + how many posts exist
CREATE VIEW IF NOT EXISTS v_notice_board_summary AS
SELECT
  nb.id AS board_id,
  nb.settlement_id,
  s.name AS settlement_name,
  nb.name AS board_name,
  nb.board_type,
  COUNT(np.id) AS active_posts
FROM notice_boards nb
JOIN settlements_v2 s ON s.id = nb.settlement_id
LEFT JOIN notice_posts np ON np.board_id = nb.id AND (np.expires_at = 0 OR np.expires_at > strftime('%s','now'))
GROUP BY nb.id, nb.settlement_id, s.name, nb.name, nb.board_type;


COMMIT;
