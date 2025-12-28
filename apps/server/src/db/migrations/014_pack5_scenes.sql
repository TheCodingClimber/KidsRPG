PRAGMA foreign_keys = ON;

BEGIN;

/* =========================================================
   PACK 5.6 — Scene Generator Hooks (Consequences -> Scenes)
   Goal:
   - After Pack 5.5 picks a consequence, we pick a "scene" template
   - Scenes feel varied: 15–20+ total to avoid repeats
   - Scenes are AI-friendly: structured meta_json + tags + hooks
   ========================================================= */


/* =========================================================
   1) Scene templates (what a scene IS)
   =========================================================
   trigger_outcome: normalized outcome (capture/retreat/etc)
   trigger_consequence_def_id: optional: only trigger after a specific consequence
   weight: base chance
   meta_json: structure the AI can follow (beats, hooks, constraints)
   ========================================================= */

CREATE TABLE IF NOT EXISTS scene_templates (
  id TEXT PRIMARY KEY,                 -- scn_capture_ransom_port
  name TEXT NOT NULL,
  trigger_outcome TEXT NOT NULL,       -- capture/knocked_out/retreat/surrender/victory/escape
  trigger_consequence_def_id TEXT NULL,-- if set, only triggers when that consequence is applied
  weight INTEGER NOT NULL DEFAULT 10,
  text_template TEXT NOT NULL,         -- what the DM says
  meta_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_scene_templates_outcome ON scene_templates(trigger_outcome);
CREATE INDEX IF NOT EXISTS idx_scene_templates_consequence ON scene_templates(trigger_consequence_def_id);


/* =========================================================
   2) Scene instances (a specific scene that happened)
   ========================================================= */

CREATE TABLE IF NOT EXISTS scene_instances (
  id TEXT PRIMARY KEY,                 -- sinst_xxx
  encounter_run_id TEXT NOT NULL,
  character_id TEXT NOT NULL,
  template_id TEXT NOT NULL,
  consequence_def_id TEXT NULL,
  text TEXT NOT NULL,
  data_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (template_id) REFERENCES scene_templates(id) ON DELETE CASCADE,
  FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
  FOREIGN KEY (encounter_run_id) REFERENCES encounter_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_scene_instances_run ON scene_instances(encounter_run_id);
CREATE INDEX IF NOT EXISTS idx_scene_instances_char ON scene_instances(character_id);


/* =========================================================
   3) Scene tags (query-friendly AI reasoning)
   ========================================================= */

CREATE TABLE IF NOT EXISTS scene_template_tags (
  template_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (template_id, tag_id),
  FOREIGN KEY (template_id) REFERENCES scene_templates(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_scene_template_tags_tag ON scene_template_tags(tag_id);


/* =========================================================
   4) Scene weight modifiers (context-sensitive variety)
   =========================================================
   - Similar philosophy to consequence_weight_mods
   - "avoid repeats" happens in query via recent history penalty
   ========================================================= */

CREATE TABLE IF NOT EXISTS scene_weight_mods (
  id TEXT PRIMARY KEY,                 -- swm_xxx
  template_id TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,

  region_id TEXT NULL,
  settlement_id TEXT NULL,
  poi_id TEXT NULL,

  min_danger INTEGER NULL,
  max_danger INTEGER NULL,

  requires_tag TEXT NULL,              -- containment check in poi meta or template meta
  weight_add INTEGER NOT NULL DEFAULT 0,
  weight_mult REAL NOT NULL DEFAULT 1.0,
  reason TEXT NOT NULL DEFAULT '',

  FOREIGN KEY (template_id) REFERENCES scene_templates(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_swm_template ON scene_weight_mods(template_id);
CREATE INDEX IF NOT EXISTS idx_swm_region ON scene_weight_mods(region_id);
CREATE INDEX IF NOT EXISTS idx_swm_settlement ON scene_weight_mods(settlement_id);
CREATE INDEX IF NOT EXISTS idx_swm_poi ON scene_weight_mods(poi_id);


/* =========================================================
   5) Resolver view: candidates with computed final_weight
   =========================================================
   We:
   - Match by trigger_outcome
   - Optionally match by consequence_def_id (if your consequence table exists)
   - Apply modifiers
   - Apply anti-repeat penalty based on last N scenes for the character
   ========================================================= */

DROP VIEW IF EXISTS v_scene_picklist;

CREATE VIEW v_scene_picklist AS
WITH run AS (
  SELECT
    er.id AS encounter_run_id,
    er.region_id,
    er.settlement_id,
    er.poi_id,
    COALESCE(
      (SELECT normalized_outcome FROM outcome_aliases WHERE raw_outcome = er.outcome),
      er.outcome
    ) AS outcome_norm
  FROM encounter_runs er
),
poi_ctx AS (
  SELECT
    p.id AS poi_id,
    p.danger AS poi_danger,
    p.meta_json AS poi_meta_json
  FROM pois p
),
-- This assumes Pack 5.4 created encounter_consequences. If not, outcome-only still works.
last_consequence AS (
  SELECT
    ec.encounter_run_id,
    ec.character_id,
    ec.consequence_def_id
  FROM encounter_consequences ec
),
recent_scene_counts AS (
  -- count how often each template_id appeared recently for each character
  SELECT
    si.character_id,
    si.template_id,
    COUNT(*) AS recent_count
  FROM scene_instances si
  WHERE si.created_at >= (strftime('%s','now') - 60*60*24*14) -- last 14 days
  GROUP BY si.character_id, si.template_id
),
base AS (
  SELECT
    r.encounter_run_id,
    lc.character_id,
    lc.consequence_def_id,
    st.id AS template_id,
    st.name AS template_name,
    st.trigger_outcome,
    st.trigger_consequence_def_id,
    st.weight AS base_weight,
    st.text_template,
    st.meta_json AS template_meta_json,
    r.region_id,
    r.settlement_id,
    r.poi_id,
    r.outcome_norm,
    COALESCE(pc.poi_danger, 0) AS poi_danger,
    COALESCE(pc.poi_meta_json, '{}') AS poi_meta_json
  FROM run r
  JOIN last_consequence lc
    ON lc.encounter_run_id = r.encounter_run_id
  JOIN scene_templates st
    ON st.trigger_outcome = r.outcome_norm
   AND (st.trigger_consequence_def_id IS NULL OR st.trigger_consequence_def_id = lc.consequence_def_id)
  LEFT JOIN poi_ctx pc
    ON pc.poi_id = r.poi_id
),
mods AS (
  SELECT
    b.*,
    swm.id AS mod_id,
    swm.weight_add,
    swm.weight_mult,
    swm.reason
  FROM base b
  LEFT JOIN scene_weight_mods swm
    ON swm.enabled = 1
   AND swm.template_id = b.template_id
   AND (swm.region_id IS NULL OR swm.region_id = b.region_id)
   AND (swm.settlement_id IS NULL OR swm.settlement_id = b.settlement_id)
   AND (swm.poi_id IS NULL OR swm.poi_id = b.poi_id)
   AND (swm.min_danger IS NULL OR b.poi_danger >= swm.min_danger)
   AND (swm.max_danger IS NULL OR b.poi_danger <= swm.max_danger)
   AND (
     swm.requires_tag IS NULL
     OR instr(COALESCE(b.poi_meta_json,'{}'), swm.requires_tag) > 0
     OR instr(COALESCE(b.template_meta_json,'{}'), swm.requires_tag) > 0
   )
),
agg AS (
  SELECT
    encounter_run_id,
    character_id,
    consequence_def_id,
    template_id,
    template_name,
    trigger_outcome,
    text_template,
    template_meta_json,
    region_id,
    settlement_id,
    poi_id,
    outcome_norm,
    poi_danger,
    base_weight,

    COALESCE(SUM(weight_add), 0) AS total_weight_add,
    COALESCE(EXP(SUM(CASE WHEN weight_mult IS NULL THEN 0 ELSE ln(weight_mult) END)), 1.0) AS total_weight_mult,

    json_group_array(
      CASE
        WHEN mod_id IS NULL THEN NULL
        ELSE json_object('modId', mod_id, 'add', weight_add, 'mult', weight_mult, 'reason', reason)
      END
    ) AS mods_json
  FROM mods
  GROUP BY encounter_run_id, character_id, template_id
)
SELECT
  a.*,

  COALESCE(rsc.recent_count, 0) AS recent_count,

  -- Anti-repeat penalty: each repeat reduces weight by 35% (tunable)
  MAX(
    0,
    CAST(
      ROUND(
        ((a.base_weight + a.total_weight_add) * a.total_weight_mult)
        * (CASE
            WHEN COALESCE(rsc.recent_count,0) = 0 THEN 1.0
            WHEN COALESCE(rsc.recent_count,0) = 1 THEN 0.65
            WHEN COALESCE(rsc.recent_count,0) = 2 THEN 0.45
            ELSE 0.30
          END)
      ) AS INTEGER
    )
  ) AS final_weight

FROM agg a
LEFT JOIN recent_scene_counts rsc
  ON rsc.character_id = a.character_id
 AND rsc.template_id = a.template_id;


/* =========================================================
   6) Seed: 20 scene templates (varied, kid-safe)
   =========================================================
   Notes:
   - meta_json.beats gives the AI a structured flow
   - meta_json.hooks tells the engine what to spawn next
   - "tone":"gentle" supports your Gentle DM + adaptive preference
   ========================================================= */

INSERT OR IGNORE INTO scene_templates
(id, name, trigger_outcome, trigger_consequence_def_id, weight, text_template, meta_json)
VALUES

-- =========================
-- CAPTURE (4)
-- =========================
('scn_capture_ransom_note', 'Ransom Note & Kind Guard', 'capture', NULL, 12,
 'You wake up in a simple holding room—not scary, just secure. A guard slides in water and a note: “No harm. Someone wants to talk.”',
 '{"tone":"gentle","beats":["wake","kind_guard","note","choice"],"choices":["negotiate","escape_plan","ask_questions"],"hooks":{"npcRole":"guard","sceneType":"negotiation"}}'),

('scn_capture_mistaken_identity', 'Mistaken Identity Mix-Up', 'capture', NULL, 10,
 'A worried captor squints at your face. “Wait… you’re not who we thought you were.” The room shifts from tense to awkward… fast.',
 '{"tone":"gentle","beats":["reveal","apology","offer_deal"],"choices":["help_them_fix","demand_release","trade_information"],"hooks":{"twist":"mistaken_identity","repChange":"positive_if_help"}}'),

('scn_capture_work_detail', 'Work Detail (Safe Task) for Freedom', 'capture', NULL, 10,
 'Instead of threats, you get an offer: “Help us with a job—carry crates, fix a wheel, fetch water—and we let you go.”',
 '{"tone":"gentle","beats":["offer","task","witness_clue","release"],"choices":["accept","bargain","refuse"],"hooks":{"miniQuest":"fetch_or_fix","loot":"small_thank_you"}}'),

('scn_capture_secretly_helped', 'Someone Slips You a Key', 'capture', NULL, 9,
 'In the quiet, a shadowed figure whispers, “Not everyone here is your enemy.” A small key skitters across the floor.',
 '{"tone":"gentle","beats":["whisper","key","escape_or_confront"],"choices":["escape","find_helper","set_trap"],"hooks":{"npcRole":"mysterious_helper","item":"key"}}'),

('scn_capture_stern_inventory', 'Stern Inventory Check (Rules First)', 'capture', NULL, 10,
 'A stern voice barks: “Hands where I can see them. No tricks.” They don’t hurt you, but they’re not friendly—rules are rules.',
 '{"tone":"stern","beats":["order","search","rules_explained","choice"],"choices":["comply","talk_your_way","observe_guard"],"hooks":{"npcRole":"guard","sceneType":"procedure"}}'),

('scn_capture_rough_questioning', 'Rough Questioning (No Harm)', 'capture', NULL, 8,
 'A captain leans in, voice like stone: “Answer straight. Waste my time and you’ll sit longer.” It’s tense… but still safe.',
 '{"tone":"gritty","beats":["questioning","pressure","reveal_option"],"choices":["truth","half_truth","redirect"],"hooks":{"storyBranch":"stern_interview","npcRole":"captain"}}'),

('scn_capture_cellmate_rival', 'Cellmate Rival (Talk or Team?)', 'capture', NULL, 9,
 'You’re not alone—someone else is here, arms crossed. “Great,” they mutter. “More trouble.”',
 '{"tone":"tense","beats":["meet_cellmate","verbal_spar","deal_or_feud"],"choices":["befriend","rivalry","ignore"],"hooks":{"npcRole":"captive","rivalChance":1}}'),

('scn_capture_bribe_offer', 'Bribe Offer (Morals Moment)', 'capture', NULL, 9,
 'A guard whispers: “Coins can open doors.” Their hand stays open… waiting.',
 '{"tone":"tense","beats":["whisper","temptation","choice"],"choices":["bribe","refuse","counter_offer"],"hooks":{"repChange":"depends","economy":"gold_sink"}}'),

('scn_capture_clean_trial', 'A Simple Trial (Tell Your Story)', 'capture', NULL, 10,
 'Instead of threats, you’re given a chance to speak. A small group listens: “Explain why you came.”',
 '{"tone":"social","beats":["gathering","story","verdict"],"choices":["apologize","justify","offer_help"],"hooks":{"npcRole":"council","repChange":"possible_positive"}}'),

('scn_capture_misdelivered_letter', 'Misdelivered Letter in Your Cell', 'capture', NULL, 9,
 'A folded letter slides under the door—clearly meant for someone else. It mentions a plan… and a name you recognize.',
 '{"tone":"mysterious","beats":["letter","clue","choice"],"choices":["return_letter","use_clue","ask_guard"],"hooks":{"clue":"letter","questSeed":"intercept_plan"}}'),

('scn_capture_food_test', 'The Food Test (Poison? No—Puzzle!)', 'capture', NULL, 9,
 'Your meal comes with a weird detail: the bread is stamped with symbols. It’s not poison—it’s a puzzle.',
 '{"tone":"mysterious","beats":["meal","symbols","solve_or_ignore"],"choices":["solve","ignore","show_cellmate"],"hooks":{"puzzle":"simple_cipher","reward":"small_key_or_info"}}'),

('scn_capture_kind_nurse', 'Kind Nurse Visit', 'capture', NULL, 10,
 'A nurse checks on you like it’s a normal day. “No one’s dying on my watch,” they say briskly.',
 '{"tone":"gentle","beats":["checkup","small_heal","hint"],"choices":["ask_for_help","stay_quiet","trade_story"],"hooks":{"itemReward":"bandage","npcRole":"nurse"}}'),

('scn_capture_guard_storytime', 'Guard Who Loves Stories', 'capture', NULL, 9,
 'A bored guard says, “Tell me a good story and I might… forget to lock something right.”',
 '{"tone":"comedy","beats":["banter","story","opportunity"],"choices":["tell_story","refuse","ask_questions"],"hooks":{"npcTrait":"easily_amused","escapeChance":1}}'),

('scn_capture_oath_contract', 'The Oath Contract', 'capture', NULL, 10,
 'A contract is offered: “Swear not to return for seven days. Break it, and every door closes to you.”',
 '{"tone":"stern","beats":["contract","oath","consequence"],"choices":["swear","negotiate_terms","refuse"],"hooks":{"worldRule":"temporary_ban","repChange":"honor"}}'),

('scn_capture_workshop_detour', 'Locked in a Workshop (Tools Nearby)', 'capture', NULL, 9,
 'They stash you in a workshop while they argue outside. Tools, scraps, and a half-built gadget sit on the bench.',
 '{"tone":"tactical","beats":["observe","improvise","choice"],"choices":["craft_lockpick","hide_tool","wait"],"hooks":{"craftHook":1,"station":"workbench"}}'),

('scn_capture_faction_emissary', 'Faction Emissary Offers Deal', 'capture', NULL, 9,
 'A well-dressed emissary arrives: “You’re valuable. Let’s handle this politely.”',
 '{"tone":"social","beats":["arrival","offer","terms"],"choices":["accept","counter","decline"],"hooks":{"factionContact":1,"questSeed":"favor_for_release"}}'),

('scn_capture_window_chance', 'High Window, Low Hope… Maybe', 'capture', NULL, 8,
 'There’s a small window—too high to reach easily. But a loose plank might make a ladder… if you’re clever.',
 '{"tone":"tense","beats":["notice_window","plan","risk"],"choices":["build_ladder","signal_help","stay_put"],"hooks":{"escapePuzzle":"simple_build","risk":"minor"}}'),

('scn_capture_false_rescue', 'False Rescue Attempt', 'capture', NULL, 8,
 'Footsteps rush in—someone tries to “help,” but they’re clumsy and loud. This could get messy… socially.',
 '{"tone":"tense","beats":["rescue_attempt","complication","choice"],"choices":["stop_them","use_chaos","hide"],"hooks":{"npcRole":"overeager_helper","comedyRisk":1}}'),

('scn_capture_hear_the_plan', 'You Overhear the Plan', 'capture', NULL, 10,
 'Through the door you hear: “Move them at dawn.” Now you have a timer—and a plan to beat.',
 '{"tone":"tense","beats":["overhear","timer","choice"],"choices":["escape_now","prepare","negotiate"],"hooks":{"timer":"dawn","pressure":1}}'),

('scn_capture_poster_on_wall', 'Wanted Poster Shock', 'capture', NULL, 7,
 'A poster on the wall shows a face… that looks a lot like someone in your party. Under it: “WANTED (Alive).”',
 '{"tone":"mysterious","beats":["poster","realization","choice"],"choices":["investigate","deny","ask_guard"],"hooks":{"twist":"mistaken_identity_or_target","questSeed":"clear_name"}}'),

-- =========================
-- KNOCKED OUT (4)
-- =========================
('scn_ko_healer_hut', 'Healer’s Hut Recovery', 'knocked_out', NULL, 14,
 'You wake up wrapped in warm blankets. A healer smiles: “Easy now. You took a hard hit. Tell me what happened.”',
 '{"tone":"gentle","beats":["wake","care","questions","gift"],"choices":["share_truth","hide_detail","ask_for_help"],"hooks":{"buildingType":"healer","itemReward":"bandage_or_tea"}}'),

('scn_ko_friendly_animals', 'Curious Forest Friends', 'knocked_out', NULL, 10,
 'A pair of curious animals watch you like you’re the strangest creature they’ve ever seen. They don’t seem dangerous… just nosy.',
 '{"tone":"whimsical","beats":["wake","animal_contact","trail_clue"],"choices":["befriend","follow","shoo_gently"],"hooks":{"creature":"small_friendly","clue":"trail_to_poi"}}'),

('scn_ko_lost_time', 'Lost Time, Strange Footprints', 'knocked_out', NULL, 9,
 'You sit up and realize time passed. Nearby: fresh footprints, a dropped trinket, and a path you don’t remember taking.',
 '{"tone":"mysterious","beats":["wake","discover_clue","choose_path"],"choices":["track","return_to_settlement","camp"],"hooks":{"clue":"footprints","spawn":"minor_rival"}}'),

('scn_ko_wake_in_ruins', 'Wake Near Ruins (Not Inside)', 'knocked_out', NULL, 8,
 'You wake beside old stones covered in moss. The air hums faintly—like the place is holding its breath.',
 '{"tone":"mysterious","beats":["wake","observe","soft_warning","hook"],"choices":["approach","mark_on_map","leave"],"hooks":{"poiType":"ruins","lootHint":"low_to_mid"}}'),

 ('scn_ko_cart_ride', 'Wagon Ride Home', 'knocked_out', NULL, 10,
 'You wake to the squeak of a wagon wheel. Someone says, “Easy—almost home.”',
 '{"tone":"gentle","beats":["wake","safe_travel","briefing"],"choices":["ask_who","rest","peek_out"],"hooks":{"returnTo":"settlement","npcRole":"driver"}}'),

('scn_ko_stolen_boot', 'One Boot Missing (Who Took It?)', 'knocked_out', NULL, 8,
 'You sit up and realize: one boot is gone. No one looks guilty… which is suspicious.',
 '{"tone":"comedy","beats":["wake","missing_item","suspects"],"choices":["investigate","laugh_it_off","barter"],"hooks":{"miniMystery":"missing_boot","reward":"trinket_or_boot"}}'),

('scn_ko_cleric_sermon', 'Cleric Gives a Lecture', 'knocked_out', NULL, 9,
 'A cleric says, “Bravery is good. Bravery with preparation is better.” Then hands you a small charm.',
 '{"tone":"warm","beats":["wake","lesson","gift"],"choices":["thank","ask_training","leave"],"hooks":{"itemReward":"minor_trinket","prepBonus":1}}'),

('scn_ko_muddy_riddle', 'Muddy Riddle at the River', 'knocked_out', NULL, 8,
 'You wake by a riverbank with a riddle carved into wet clay. Weirdly… it feels meant for you.',
 '{"tone":"mysterious","beats":["wake","riddle","choice"],"choices":["solve","copy","ignore"],"hooks":{"puzzle":"riddle","questSeed":"follow_answer"}}'),

('scn_ko_companion_carry', 'Companion Carried You', 'knocked_out', NULL, 10,
 'Your companion looks exhausted. “Don’t scare me like that again,” they mutter—then smiles.',
 '{"tone":"relationship","beats":["wake","bond","promise"],"choices":["apologize","plan_training","joke"],"hooks":{"companionAffinity":6}}'),

('scn_ko_snow_blanket', 'Snow Blanket, Warm Fire', 'knocked_out', NULL, 8,
 'You wake under a blanket while snow falls softly. A campfire crackles nearby.',
 '{"tone":"gentle","beats":["wake","warmth","choice"],"choices":["rest_more","travel","talk"],"hooks":{"campRest":"small_bonus"}}'),

('scn_ko_birds_warning', 'Birds Give a Warning', 'knocked_out', NULL, 7,
 'Birds circle and call strangely—almost like an alarm. Something nearby is moving.',
 '{"tone":"tense","beats":["wake","warning","choice"],"choices":["hide","leave","observe"],"hooks":{"futureEncounter":"avoidable_if_careful"}}'),

('scn_ko_bandage_art', 'Bandages with Little Doodles', 'knocked_out', NULL, 9,
 'Someone bandaged you… and doodled smiling suns on the cloth. It’s oddly comforting.',
 '{"tone":"gentle","beats":["wake","notice","gratitude"],"choices":["thank","find_artist","move_on"],"hooks":{"npcRole":"kid_or_healer","repChange":"small_positive"}}'),

('scn_ko_ruin_echo', 'A Ruin Echoes Your Name', 'knocked_out', NULL, 6,
 'As you wake, you swear the wind says your name. The nearby ruins feel… aware.',
 '{"tone":"mysterious","beats":["wake","whisper","choice"],"choices":["approach","mark_map","avoid"],"hooks":{"poiType":"ruins","mystery":"sentient_place"}}'),

('scn_ko_lucky_find', 'You Landed on a Lucky Coin', 'knocked_out', NULL, 9,
 'You sit up and find a shiny coin pressed into the dirt. Lucky… or bait?',
 '{"tone":"mysterious","beats":["wake","find","choice"],"choices":["take","inspect","leave"],"hooks":{"loot":"small_gold","trapChance":"low"}}'),

('scn_ko_kind_ranger', 'Ranger Checks the Trail', 'knocked_out', NULL, 9,
 'A ranger says, “You’re safe. I moved you off the path.” They point to fresh tracks.',
 '{"tone":"helpful","beats":["wake","info","choice"],"choices":["follow_tracks","return_town","camp"],"hooks":{"clue":"tracks","npcRole":"ranger"}}'),

('scn_ko_shared_soup', 'Soup and Questions', 'knocked_out', NULL, 9,
 'Warm soup. Warm eyes. “So… what were you doing out there?”',
 '{"tone":"social","beats":["wake","care","story"],"choices":["tell_story","ask_for_rumors","stay_private"],"hooks":{"rumor":1}}'),

('scn_ko_herbalist_trade', 'Herbalist Trades Advice', 'knocked_out', NULL, 8,
 'An herbalist says, “Bring me two herbs next time and I’ll teach you something useful.”',
 '{"tone":"social","beats":["wake","deal","hook"],"choices":["accept","negotiate","decline"],"hooks":{"questSeed":"herb_fetch","recipeUnlock":"basic_tonic"}}'),

('scn_ko_dream_map', 'Dream Map Fragment', 'knocked_out', NULL, 7,
 'You remember a dream—clear as a map. A place with three stones… and a hollow tree.',
 '{"tone":"mysterious","beats":["wake","dream","choice"],"choices":["write_it_down","ask_companion","ignore"],"hooks":{"clue":"dream_map","poiHint":"hidden_cache"}}'),

('scn_ko_misplaced_pack', 'Your Pack Is Rearranged', 'knocked_out', NULL, 8,
 'Your pack is back… but things are neatly sorted in a way you didn’t do.',
 '{"tone":"mysterious","beats":["wake","notice","choice"],"choices":["check_inventory","thank_helper","suspect_thief"],"hooks":{"inventory":"reordered","npcMystery":1}}'),

('scn_ko_bell_chime', 'A Bell Chimes Far Away', 'knocked_out', NULL, 7,
 'A bell rings in the distance. It feels like an invitation… or a warning.',
 '{"tone":"mysterious","beats":["wake","bell","choice"],"choices":["go_toward","avoid","ask_locals"],"hooks":{"eventHint":"settlement_event"}}'),

-- =========================
-- RETREAT (4)
-- =========================
('scn_retreat_shortcut_map', 'A Shortcut Map Appears', 'retreat', NULL, 12,
 'As you pull back, you spot something you missed earlier: a scratched map on a rock showing a safer route.',
 '{"tone":"helpful","beats":["retreat","discover_map","plan"],"choices":["take_shortcut","warn_town","return_prepared"],"hooks":{"mapUnlock":"safer_route","prepBonus":1}}'),

('scn_retreat_rumor_inn', 'Inn Rumor & Friendly Warning', 'retreat', NULL, 11,
 'Back in town, someone overhears your story and leans in: “That place? A trick to it. Want the secret?”',
 '{"tone":"social","beats":["return","rumor","trade_info"],"choices":["pay","help_npc","promise_favor"],"hooks":{"npcRole":"rumor_spreader","info":"counter_to_enemy"}}'),

('scn_retreat_trap_notice', 'You Notice Their Trap Pattern', 'retreat', NULL, 9,
 'While escaping, you realize their ambush had a pattern. Next time, you can predict it.',
 '{"tone":"tactical","beats":["retreat","pattern","future_advantage"],"choices":["set_counter_ambush","craft_tools","recruit_help"],"hooks":{"prepTag":"enemy_pattern_known"}}'),

('scn_retreat_companion_bond', 'Companion Moment', 'retreat', NULL, 9,
 'During the retreat, your companion says quietly, “You didn’t panic. That’s why we’re okay.” Something clicks—teamwork improves.',
 '{"tone":"warm","beats":["retreat","talk","bond"],"choices":["train_together","share_goal","upgrade_gear"],"hooks":{"bondBonus":1,"companionAffinity":5}}'),
 
('scn_retreat_safehouse', 'A Safehouse Door Opens', 'retreat', NULL, 10,
 'A hidden door opens and a hand pulls you inside: “Quiet. You can breathe now.”',
 '{"tone":"tense","beats":["retreat","hide","explain"],"choices":["thank","ask_who","rest"],"hooks":{"safehouse":1,"npcRole":"helper"}}'),

('scn_retreat_merchant_tip', 'Merchant Tip (Right Tool)', 'retreat', NULL, 10,
 'A merchant says, “Next time? Bring rope and chalk. Trust me.”',
 '{"tone":"helpful","beats":["return","advice","prep"],"choices":["buy_tools","ask_more","ignore"],"hooks":{"prepTag":"bring_tools","shopHint":"general"}}'),

('scn_retreat_guard_scolding', 'Guard Scolding (But Respect)', 'retreat', NULL, 8,
 'A guard scolds you: “You’re brave, not wise.” Then quietly adds, “Come back with backup.”',
 '{"tone":"stern","beats":["scold","respect","hook"],"choices":["recruit_help","train","plan"],"hooks":{"npcRole":"guard","questSeed":"hire_backup"}}'),

('scn_retreat_new_rival', 'New Rival Saw You Run', 'retreat', NULL, 7,
 'Someone smirks as you pass: “Running already?” They might become a rival… or a weird friend.',
 '{"tone":"tense","beats":["public_moment","rival_hook"],"choices":["challenge","ignore","befriend"],"hooks":{"rivalChance":1,"settlementGossip":1}}'),

('scn_retreat_supplies_low', 'Supplies Running Low', 'retreat', NULL, 9,
 'You realize you used more supplies than expected. Next time you’ll need better planning.',
 '{"tone":"tactical","beats":["inventory_check","lesson","plan"],"choices":["craft","shop","rest"],"hooks":{"prepBonus":1,"resourceSink":1}}'),

('scn_retreat_map_marker', 'You Mark the Trail', 'retreat', NULL, 10,
 'You carve a simple trail mark so you can return without getting lost.',
 '{"tone":"helpful","beats":["retreat","mark","future"],"choices":["return_later","share_mark","hide_mark"],"hooks":{"mapUnlock":"trail_marker"}}'),

('scn_retreat_scout_report', 'Scout Report Available', 'retreat', NULL, 9,
 'A scout offers a report: “For a few coins, I’ll tell you what’s really out there.”',
 '{"tone":"social","beats":["offer","info","choice"],"choices":["pay","do_favor","decline"],"hooks":{"info":"enemy_count_approx","economy":"gold_sink"}}'),

('scn_retreat_training_yard', 'Training Yard Invitation', 'retreat', NULL, 9,
 'Someone points to a training yard: “Come back stronger. We can help.”',
 '{"tone":"warm","beats":["retreat","invite","goal"],"choices":["train_now","schedule","decline"],"hooks":{"training":1,"buff":"minor"}}'),

('scn_retreat_weather_turn', 'Weather Turns (Time Pressure)', 'retreat', NULL, 8,
 'The wind shifts. Bad weather is coming. You’ll need to act soon—either return prepared or wait it out.',
 '{"tone":"tense","beats":["retreat","weather","choice"],"choices":["prepare_fast","rest_wait","seek_shelter"],"hooks":{"timer":"weather","travelEffect":"harder"}}'),

('scn_retreat_supply_cache', 'You Find a Tiny Supply Cache', 'retreat', NULL, 8,
 'Behind a rock: a tiny cache—rope scraps, a candle, and a note: “For travelers.”',
 '{"tone":"gentle","beats":["find","gratitude","choice"],"choices":["take","leave_some","investigate"],"hooks":{"loot":"small","mystery":"who_left_it"}}'),

('scn_retreat_companion_fear', 'Companion Admits Fear', 'retreat', NULL, 8,
 'A companion says quietly, “I was scared.” Honest fear makes plans better.',
 '{"tone":"relationship","beats":["retreat","confession","plan"],"choices":["encourage","adjust_plan","rest"],"hooks":{"companionAffinity":5,"prepBonus":1}}'),

('scn_retreat_enemy_message', 'Enemy Sends a Message', 'retreat', NULL, 6,
 'A note is left where you fled: “We’re not done.” It’s not a threat… it’s an invitation to a rivalry.',
 '{"tone":"tense","beats":["message","meaning","choice"],"choices":["ignore","respond","prepare"],"hooks":{"rivalChance":1,"questSeed":"rival_arc"}}'),

('scn_retreat_friendly_cart', 'A Friendly Cart Offers Ride', 'retreat', NULL, 8,
 'A cart driver offers a ride and a warning: “That road ahead? Trouble.”',
 '{"tone":"helpful","beats":["retreat","ride","warning"],"choices":["take_ride","ask_details","decline"],"hooks":{"travel":"safe_return"}}'),

('scn_retreat_new_job_board', 'Job Board Updates', 'retreat', NULL, 9,
 'The job board has new postings—some connected to what you just saw.',
 '{"tone":"social","beats":["return","board","hook"],"choices":["take_job","ask_npc","ignore"],"hooks":{"questSeed":"related_bounty"}}'),

('scn_retreat_small_victory', 'Small Victory Awarded', 'retreat', NULL, 9,
 'Even though you retreated, you saved someone or learned something. You gain a small reward—because smart choices matter.',
 '{"tone":"warm","beats":["validation","reward","plan"],"choices":["continue","rest","craft"],"hooks":{"reward":"small","repChange":"positive"}}'),

('scn_retreat_guild_offer', 'Guild Offers Help (For a Price)', 'retreat', NULL, 7,
 'A guild rep says, “We can support you… for the right contract.”',
 '{"tone":"stern","beats":["offer","terms","choice"],"choices":["accept","negotiate","decline"],"hooks":{"factionContact":1,"economy":"contract"}}'),

-- =========================
-- SURRENDER (2)
-- =========================
('scn_surrender_terms', 'Surrender Terms & Honor', 'surrender', NULL, 12,
 'They accept your surrender with surprising honor: “No harm. Give your word you’ll leave—and we’ll trade you something fair.”',
 '{"tone":"gentle","beats":["surrender","terms","trade"],"choices":["swear_oath","negotiate","refuse"],"hooks":{"trade":"fair","repChange":"positive_if_honor"}}'),

('scn_surrender_interview', 'The Interview', 'surrender', NULL, 9,
 'Instead of chains, you get questions. “Why are you here? Who sent you?” The answers shape what happens next.',
 '{"tone":"social","beats":["surrender","questions","reveal"],"choices":["truth","half_truth","misdirect"],"hooks":{"storyBranch":"interrogation"}}'),

('scn_surrender_blindfold_walk', 'Blindfold Walk (No Harm)', 'surrender', NULL, 9,
 'They blindfold you—not cruelly, but firmly. “No peeking. Rules.” You’re led somewhere safe… for now.',
 '{"tone":"stern","beats":["blindfold","walk","arrival","choice"],"choices":["listen","talk","stay_silent"],"hooks":{"mystery":"location_unknown","npcRole":"escort"}}'),

('scn_surrender_exchange_item', 'Exchange Item for Freedom', 'surrender', NULL, 10,
 'They offer a trade: “Give us something useful—rope, rations, coin—and you walk.”',
 '{"tone":"social","beats":["offer","trade","release"],"choices":["pay","barter","refuse"],"hooks":{"economy":"resource_sink","repChange":"neutral"}}'),

('scn_surrender_story_swap', 'Story Swap (Respect Earned)', 'surrender', NULL, 9,
 'Their leader says, “Tell me who you are.” If your story rings true, the mood softens.',
 '{"tone":"social","beats":["leader","story","respect"],"choices":["truth","half_truth","joke"],"hooks":{"repChange":"positive_if_honest"}}'),

('scn_surrender_mercy_marker', 'Mercy Marker (A Visible Sign)', 'surrender', NULL, 7,
 'They mark your cloak with a simple symbol. “This means you were spared. Don’t waste it.”',
 '{"tone":"stern","beats":["mark","meaning","choice"],"choices":["keep_symbol","remove_later","ask_about_it"],"hooks":{"worldFlag":"spared_once"}}'),

('scn_surrender_task_token', 'Task Token (Do One Favor)', 'surrender', NULL, 9,
 'Instead of punishment, you get a token: “Do one favor for us later. Bring this back as proof.”',
 '{"tone":"tense","beats":["token","favor","release"],"choices":["accept","negotiate","refuse"],"hooks":{"questSeed":"favor_debt","item":"token"}}'),

('scn_surrender_witness_oath', 'Witnessed Oath', 'surrender', NULL, 8,
 'A witness arrives to hear your oath. “Speak clearly. Words matter.”',
 '{"tone":"stern","beats":["witness","oath","terms"],"choices":["swear","ask_terms","refuse"],"hooks":{"repChange":"honor"}}'),

('scn_surrender_medic_help', 'Medic Helps the Wounded', 'surrender', NULL, 8,
 'They let you help bandage someone. It’s quiet work—and it changes how they look at you.',
 '{"tone":"warm","beats":["help","respect","choice"],"choices":["help_more","ask_questions","leave"],"hooks":{"repChange":"positive","itemReward":"bandage"}}'),

('scn_surrender_prisoner_swap', 'Prisoner Swap Offer', 'surrender', NULL, 7,
 'They suggest a swap: “You walk if you carry a message.”',
 '{"tone":"tense","beats":["offer","message","choice"],"choices":["carry_message","refuse","negotiate"],"hooks":{"questSeed":"deliver_message"}}'),

('scn_surrender_clean_release', 'Clean Release (No Strings)', 'surrender', NULL, 9,
 'They simply let you go. “Not everyone wants blood or misery. Leave.”',
 '{"tone":"gentle","beats":["release","relief","hook"],"choices":["leave","thank","watch"],"hooks":{"mystery":"why_spare"}}'),

('scn_surrender_hostile_crowd', 'Hostile Crowd (But Protected)', 'surrender', NULL, 7,
 'A crowd jeers, but guards keep them back. “No harm,” the captain growls. “I said no harm.”',
 '{"tone":"gritty","beats":["crowd","protection","exit"],"choices":["keep_head_down","speak","leave_fast"],"hooks":{"settlementGossip":1}}'),

('scn_surrender_confiscate_weapon', 'Weapon Confiscated (Temporary)', 'surrender', NULL, 10,
 'They take your weapon—but give a receipt: “Return it later if you behave.”',
 '{"tone":"stern","beats":["confiscate","receipt","choice"],"choices":["accept","argue","request_exception"],"hooks":{"inventory":"temp_confiscation","returnCondition":"good_behavior"}}'),

('scn_surrender_offer_join', 'Offer to Join (Awkward)', 'surrender', NULL, 6,
 'Someone says, “You’re brave. Ever think of joining us?” It’s… not what you expected.',
 '{"tone":"social","beats":["offer","reaction","choice"],"choices":["decline_politely","ask_questions","pretend_consider"],"hooks":{"recruitmentHook":1}}'),

('scn_surrender_test_of_honesty', 'Test of Honesty', 'surrender', NULL, 8,
 'They ask the same question twice at different times—watching your answer.',
 '{"tone":"tense","beats":["question1","question2","result"],"choices":["consistent","change_story","admit"],"hooks":{"storyBranch":"trust"}}'),

('scn_surrender_lost_and_found', 'Lost & Found Return', 'surrender', NULL, 7,
 'They return a lost item you dropped earlier. “We’re not thieves,” someone mutters.',
 '{"tone":"warm","beats":["return_item","surprise","choice"],"choices":["thank","suspect_trick","ask_why"],"hooks":{"repChange":"positive"}}'),

('scn_surrender_chalk_circle', 'Chalk Circle Promise', 'surrender', NULL, 7,
 'They draw a chalk circle: “Step out and we’ll assume you’re lying. Stay in, and we talk.”',
 '{"tone":"stern","beats":["rule","choice","talk"],"choices":["stay","step_out","negotiate"],"hooks":{"sceneType":"trust_test"}}'),

('scn_surrender_confession_opens_door', 'Confession Opens a Door', 'surrender', NULL, 7,
 'When you admit something small, the leader relaxes. “Honest kids are rare.”',
 '{"tone":"relationship","beats":["confession","soften","deal"],"choices":["continue_truth","ask_help","leave"],"hooks":{"repChange":"positive","npcBond":1}}'),

('scn_surrender_stamp_pass', 'Stamped Pass for Travel', 'surrender', NULL, 6,
 'They stamp a travel pass: “Show this and you won’t be bothered for a while.”',
 '{"tone":"helpful","beats":["stamp","explain","choice"],"choices":["use_pass","ask_limit","trade_pass"],"hooks":{"worldFlag":"temporary_safe_pass"}}'),

('scn_surrender_secret_warning', 'Secret Warning Whisper', 'surrender', NULL, 6,
 'A guard whispers as you leave: “Don’t go back there at night.”',
 '{"tone":"mysterious","beats":["whisper","warning","hook"],"choices":["ask_why","leave","tell_party"],"hooks":{"eventHint":"night_danger"}}'),~

-- =========================
-- VICTORY (4)
-- =========================
('scn_victory_hidden_cache', 'Hidden Cache Found', 'victory', NULL, 12,
 'After the dust settles, you notice a loose stone and a hollow sound beneath it. Something was hidden here.',
 '{"tone":"rewarding","beats":["victory","discover_cache","choice"],"choices":["loot","mark","share"],"hooks":{"lootTier":"mid","trinketChance":1}}'),

('scn_victory_rescued_npc', 'Rescued Someone!', 'victory', NULL, 10,
 'A frightened traveler steps out from hiding. “I thought I’d never get out… thank you.”',
 '{"tone":"warm","beats":["victory","rescue","gratitude","hook"],"choices":["escort","ask_for_info","recruit"],"hooks":{"npcRole":"traveler","companionOffer":1}}'),

('scn_victory_faction_notice', 'A Faction Takes Notice', 'victory', NULL, 9,
 'Word travels fast. A messenger arrives with a seal: “Our faction heard what you did. We’d like to offer a task… and a reward.”',
 '{"tone":"prestige","beats":["victory","message","offer"],"choices":["accept","decline","ask_more"],"hooks":{"factionRep":5,"questSeed":"faction_task"}}'),

('scn_victory_trophy_craft', 'Trophy Craft Idea', 'victory', NULL, 9,
 'Looking at the remains of the challenge, you realize parts could be crafted into something special.',
 '{"tone":"crafty","beats":["victory","idea","recipe_unlock"],"choices":["harvest","save_for_later","ask_crafter"],"hooks":{"recipeUnlock":"trophy_item","materials":"monster_parts"}}'),

('scn_victory_cheer_in_town', 'Town Cheers (Tiny Parade)', 'victory', NULL, 9,
 'Back in town, someone starts clapping… then more join in. It’s not huge, but it feels real.',
 '{"tone":"warm","beats":["return","cheer","reward"],"choices":["accept_praise","share_credit","stay_humble"],"hooks":{"repChange":"positive","event":"small_celebration"}}'),

('scn_victory_map_update', 'Map Updates Itself (Magic Ink)', 'victory', NULL, 7,
 'Your map gains a new mark like invisible ink finally revealed. The world is… responding.',
 '{"tone":"mysterious","beats":["discover","map_update","hook"],"choices":["follow_new_mark","ask_mage","wait"],"hooks":{"mapUnlock":"new_poi_hint"}}'),

('scn_victory_loot_choice', 'Choose One Treasure', 'victory', NULL, 9,
 'You find three treasures, but can safely take only one without slowing down.',
 '{"tone":"tactical","beats":["find_three","choose_one","consequence"],"choices":["take_A","take_B","take_C"],"hooks":{"loot":"choice_bundle","anti_greed":1}}'),

('scn_victory_enemy_mercy', 'Enemy Shows Mercy', 'victory', NULL, 7,
 'A defeated foe lowers their weapon. “You could’ve been cruel. You weren’t.”',
 '{"tone":"relationship","beats":["mercy","respect","hook"],"choices":["spare","recruit","warn"],"hooks":{"rivalOrFriend":1}}'),

('scn_victory_found_herbs', 'Rare Herbs Nearby', 'victory', NULL, 9,
 'After the fight, you notice herbs growing in a safe patch—like a reward from nature itself.',
 '{"tone":"helpful","beats":["notice","harvest","future"],"choices":["harvest","mark_location","share"],"hooks":{"loot":"herbs","station":"alchemy"}}'),

('scn_victory_weapon_nick', 'Weapon Gets a Nick', 'victory', NULL, 8,
 'Your weapon has a small nick. Not broken—just a reminder. A smith could improve it.',
 '{"tone":"tactical","beats":["notice_damage","choice"],"choices":["repair_now","visit_smith","ignore"],"hooks":{"repairHook":1}}'),

('scn_victory_companion_pride', 'Companion Pride', 'victory', NULL, 9,
 'Your companion says, “That was… actually awesome.” Their confidence rises.',
 '{"tone":"warm","beats":["praise","bond","plan_next"],"choices":["celebrate","train","rest"],"hooks":{"companionAffinity":6}}'),

('scn_victory_secret_door', 'Secret Door Click', 'victory', NULL, 8,
 'A stone shifts with a click, revealing a narrow hidden door.',
 '{"tone":"mysterious","beats":["click","reveal","choice"],"choices":["enter","mark_map","block_it"],"hooks":{"poiHint":"hidden_room","lootTier":"mid"}}'),

('scn_victory_bounty_stamp', 'Bounty Stamp (Official Credit)', 'victory', NULL, 8,
 'A clerk stamps your bounty sheet: “Verified.” It feels legit—like you’re becoming real heroes.',
 '{"tone":"social","beats":["paperwork","reward","hook"],"choices":["collect_gold","ask_new_jobs","rest"],"hooks":{"economy":"bounty_pay","questSeed":"next_bounty"}}'),

('scn_victory_new_recipe', 'New Recipe Idea', 'victory', NULL, 9,
 'You realize you can craft something from what you found—if you had the right station.',
 '{"tone":"crafty","beats":["idea","requirements","hook"],"choices":["seek_station","store_parts","ask_crafter"],"hooks":{"recipeUnlock":"new_item","craftHook":1}}'),

('scn_victory_letter_of_thanks', 'Letter of Thanks', 'victory', NULL, 7,
 'A simple letter arrives later: “Thank you.” No reward, just meaning.',
 '{"tone":"warm","beats":["receive_letter","reflect","hook"],"choices":["reply","visit_sender","keep"],"hooks":{"npcBond":1}}'),

('scn_victory_festival_invite', 'Festival Invite', 'victory', NULL, 6,
 'Someone invites you to a local festival. “Heroes should eat, too.”',
 '{"tone":"warm","beats":["invite","event","choice"],"choices":["go","decline","ask_details"],"hooks":{"event":"settlement_festival"}}'),

('scn_victory_trinket_glimmer', 'Trinket Glimmers', 'victory', NULL, 8,
 'A trinket you found glimmers softly. It might awaken later…',
 '{"tone":"mysterious","beats":["glimmer","hint","hook"],"choices":["inspect","ask_alchemist","stash"],"hooks":{"trinketAwaken":1}}'),

('scn_victory_children_follow', 'Kids Follow You (Adoring)', 'victory', NULL, 5,
 'A couple kids try to follow you around asking questions. It’s adorable—and distracting.',
 '{"tone":"comedy","beats":["follow","questions","choice"],"choices":["answer","shoo_gently","take_to_guard"],"hooks":{"settlementFlavor":1}}'),

('scn_victory_faction_discount', 'Faction Discount', 'victory', NULL, 6,
 'A shopkeeper says, “Heard what you did. I’ll knock a little off the price.”',
 '{"tone":"warm","beats":["recognition","discount","hook"],"choices":["buy_now","save_later","ask_rumors"],"hooks":{"economy":"discount","repChange":"positive"}}'),

('scn_victory_rival_promise', 'Rival Promise', 'victory', NULL, 6,
 'A rival hears of your victory and smirks: “Next time, I win.”',
 '{"tone":"tense","beats":["rival","promise","hook"],"choices":["challenge_back","ignore","befriend"],"hooks":{"rivalChance":1}}'),
-- =========================
-- ESCAPE (2)
-- =========================
('scn_escape_river_route', 'Escape via River Route', 'escape', NULL, 11,
 'You slip away along a river path. It’s cold, but it hides your trail. Ahead: a fork—safe and slow, or risky and fast.',
 '{"tone":"tense_but_safe","beats":["escape","river","fork"],"choices":["safe","fast"],"hooks":{"travelEffect":"stealth_bonus","futureEncounter":"reduced"}}'),

('scn_escape_dropped_pursuit', 'They Stop Chasing', 'escape', NULL, 10,
 'You expect footsteps behind you… but the chase ends. Either they’re confident you’ll return… or something else scared them off.',
 '{"tone":"mysterious","beats":["escape","silence","implication"],"choices":["leave_now","observe","set_watch"],"hooks":{"mystery":"third_party_present"}}'),

('scn_escape_smoke_and_laughter', 'Smoke and Laughter (Distraction)', 'escape', NULL, 9,
 'Someone nearby knocks over a pot and shouts nonsense. Confusion spreads—and you slip away.',
 '{"tone":"comedy","beats":["distraction","slip_away","choice"],"choices":["run_far","hide_near","circle_back"],"hooks":{"escapeAid":"distraction"}}'),

('scn_escape_rooftop_dash', 'Rooftop Dash', 'escape', NULL, 7,
 'You scramble up onto low roofs—fast, risky, but effective. The city turns into a maze.',
 '{"tone":"tense","beats":["climb","dash","drop_down"],"choices":["keep_roof","hide","return_to_party"],"hooks":{"travelEffect":"fast_escape","risk":"minor"}}'),

('scn_escape_under_bridge', 'Under the Bridge', 'escape', NULL, 9,
 'You duck under a bridge and hold your breath. Footsteps pass overhead… then fade.',
 '{"tone":"stealthy","beats":["hide","listen","relief"],"choices":["wait_longer","move_now","signal_party"],"hooks":{"stealthBonus":1}}'),

('scn_escape_friendly_door', 'Friendly Door Opens', 'escape', NULL, 8,
 'A door cracks open and a voice whispers, “Inside. Now.”',
 '{"tone":"tense","beats":["invited_hide","choice","deal"],"choices":["enter","refuse","ask_who"],"hooks":{"safehouse":1,"npcRole":"stranger"}}'),

('scn_escape_wrong_turn_luck', 'Wrong Turn, Lucky Find', 'escape', NULL, 8,
 'You take a wrong turn—and find a stash of supplies tucked behind crates.',
 '{"tone":"mysterious","beats":["wrong_turn","stash","choice"],"choices":["take","leave","mark"],"hooks":{"loot":"small","reward":"luck"}}'),

('scn_escape_split_path', 'Split Path Decision', 'escape', NULL, 9,
 'Two paths: one loud but open, one quiet but tight. You choose quickly.',
 '{"tone":"tense","beats":["choice","movement","result"],"choices":["loud","quiet"],"hooks":{"branch":"escape_route"}}'),

('scn_escape_hide_in_wagon', 'Hide in a Wagon', 'escape', NULL, 8,
 'You hop into a wagon of hay. It smells terrible—but it works.',
 '{"tone":"comedy","beats":["wagon","hold_breath","escape"],"choices":["stay","jump_out_early","peek"],"hooks":{"travel":"safe_exit"}}'),

('scn_escape_cat_guide', 'A Cat Leads the Way', 'escape', NULL, 7,
 'A cat appears, meows once, and trots like it expects you to follow.',
 '{"tone":"whimsical","beats":["cat","follow","secret_route"],"choices":["follow","ignore","befriend"],"hooks":{"guide":"cat","route":"hidden"}}'),

('scn_escape_crowd_cover', 'Crowd Cover', 'escape', NULL, 9,
 'You blend into a crowd. Someone bumps you—then whispers, “Keep walking.”',
 '{"tone":"stealthy","beats":["blend","assist","exit"],"choices":["keep_walking","turn_corner","meet_helper"],"hooks":{"npcRole":"helper_in_crowd"}}'),

('scn_escape_drop_decoy', 'Drop a Decoy', 'escape', NULL, 8,
 'You toss a decoy pouch. Pursuers chase the wrong sound.',
 '{"tone":"tactical","beats":["decoy","misdirect","escape"],"choices":["run","hide","double_back"],"hooks":{"prepTag":"decoy_used"}}'),

('scn_escape_lost_hat', 'You Lose Your Hat', 'escape', NULL, 6,
 'You escape… but your hat is gone. Not tragic—just annoying. Also: it might be a clue later.',
 '{"tone":"comedy","beats":["escape","lost_item","hook"],"choices":["ignore","return_later","ask_around"],"hooks":{"miniQuest":"recover_hat"}}'),

('scn_escape_hear_rival', 'You Hear a Rival Laugh', 'escape', NULL, 6,
 'Somewhere behind you, someone laughs like they know you. That… is not comforting.',
 '{"tone":"tense","beats":["sound","unease","hook"],"choices":["run_faster","hide","confront"],"hooks":{"rivalChance":1}}'),

('scn_escape_herb_smell', 'Herb Smell Masks You', 'escape', NULL, 7,
 'You roll through a patch of strong-smelling herbs. Your trail becomes harder to follow.',
 '{"tone":"helpful","beats":["herbs","mask_scent","escape"],"choices":["keep_moving","harvest","hide"],"hooks":{"stealthBonus":1,"loot":"herb_small"}}'),

('scn_escape_swim_option', 'Cold Water Option', 'escape', NULL, 6,
 'A stream blocks the path. Cold water could hide you—if you dare.',
 '{"tone":"tense","beats":["stream","decision","result"],"choices":["swim","bridge","hide"],"hooks":{"travelEffect":"trail_lost"}}'),

('scn_escape_party_signal', 'Signal Your Party', 'escape', NULL, 9,
 'You manage a quick signal—bird call, whistle, or hand sign. Coordination saves you.',
 '{"tone":"tactical","beats":["signal","response","regroup"],"choices":["regroup","keep_solo","set_meet_point"],"hooks":{"partyCoordination":1}}'),

('scn_escape_good_samaritan', 'Good Samaritan Offers Cloak', 'escape', NULL, 6,
 'A traveler offers a cloak: “Put this on. Blend in.”',
 '{"tone":"gentle","beats":["offer","blend","escape"],"choices":["accept","decline","trade"],"hooks":{"item":"cloak_temp","stealthBonus":1}}'),

('scn_escape_hayloft', 'Hide in a Hayloft', 'escape', NULL, 7,
 'You climb into a hayloft and go still. Dust floats in the light like tiny stars.',
 '{"tone":"stealthy","beats":["climb","hide","relief"],"choices":["wait","leave_now","watch"],"hooks":{"stealthBonus":1}}'),

('scn_escape_small_bridge_troll', 'A Tiny Bridge “Troll”', 'escape', NULL, 5,
 'A very small creature blocks a bridge and demands… a joke. Yes, a joke.',
 '{"tone":"comedy","beats":["blocked","tell_joke","pass"],"choices":["tell_joke","offer_snack","find_way"],"hooks":{"npcRole":"tiny_bridge_guard","passage":"earned"}}');

/* =========================================================
   7) Seed some helpful tags (optional)
   ========================================================= */

-- Add a few tags if you want richer querying
INSERT OR IGNORE INTO tags (id, label) VALUES
('scene:gentle', 'Gentle Scene'),
('scene:whimsical', 'Whimsical Scene'),
('scene:mysterious', 'Mysterious Scene'),
('scene:social', 'Social Scene'),
('scene:tactical', 'Tactical Scene'),
('scene:rewarding', 'Rewarding Scene'),
('scene:crafting_hook', 'Crafting Hook'),
('scene:stern', 'Stern Scene'),
('scene:tense', 'Tense Scene'),
('scene:gritty', 'Gritty (Kid-Safe) Scene'),
('scene:comedy', 'Comedic Scene'),
('scene:investigation', 'Investigation Scene'),
('scene:relationship', 'Relationship Scene'),
('scene:stealth', 'Stealth Scene');

-- Tag a few templates (example pattern)
INSERT OR IGNORE INTO scene_template_tags (template_id, tag_id) VALUES
('scn_capture_ransom_note', 'scene:gentle'),
('scn_capture_mistaken_identity', 'scene:social'),
('scn_capture_work_detail', 'scene:gentle'),
('scn_capture_secretly_helped', 'scene:mysterious'),
('scn_ko_friendly_animals', 'scene:whimsical'),
('scn_ko_lost_time', 'scene:mysterious'),
('scn_retreat_trap_notice', 'scene:tactical'),
('scn_victory_trophy_craft', 'scene:crafting_hook'),
('scn_ko_stolen_boot','scene:comedy'),
('scn_ko_companion_carry','scene:relationship'),
('scn_ko_muddy_riddle','scene:investigation'),
('scn_ko_birds_warning','scene:tense'),
('scn_ko_dream_map','scene:mysterious'),
('scn_capture_stern_inventory','scene:stern'),
('scn_capture_rough_questioning','scene:gritty'),
('scn_capture_oath_contract','scene:stern'),
('scn_capture_hear_the_plan','scene:tense'),
('scn_capture_workshop_detour','scene:tactical'),
('scn_capture_food_test','scene:investigation'),
('scn_capture_guard_storytime','scene:comedy'),
('scn_ko_stolen_boot','scene:comedy'),
('scn_ko_companion_carry','scene:relationship'),
('scn_ko_muddy_riddle','scene:investigation'),
('scn_ko_birds_warning','scene:tense'),
('scn_ko_dream_map','scene:mysterious'),
('scn_retreat_guard_scolding','scene:stern'),
('scn_retreat_weather_turn','scene:tense'),
('scn_retreat_companion_fear','scene:relationship'),
('scn_retreat_scout_report','scene:investigation'),
('scn_retreat_safehouse','scene:stealth'),
('scn_surrender_blindfold_walk','scene:stern'),
('scn_surrender_hostile_crowd','scene:gritty'),
('scn_surrender_test_of_honesty','scene:investigation'),
('scn_surrender_confiscate_weapon','scene:stern'),
('scn_surrender_clean_release','scene:gentle'),
('scn_victory_secret_door','scene:investigation'),
('scn_victory_new_recipe','scene:crafting_hook'),
('scn_victory_rival_promise','scene:tense'),
('scn_victory_cheer_in_town','scene:relationship'),
('scn_victory_children_follow','scene:comedy'),
('scn_escape_under_bridge','scene:stealth'),
('scn_escape_crowd_cover','scene:stealth'),
('scn_escape_split_path','scene:tense'),
('scn_escape_drop_decoy','scene:tactical'),
('scn_escape_small_bridge_troll','scene:comedy');



/* =========================================================
   8) Seed a few scene weight modifiers (optional examples)
   ========================================================= */

-- Bandit-themed POIs boost certain retreat scenes
INSERT OR IGNORE INTO scene_weight_mods
(id, template_id, enabled, requires_tag, weight_add, weight_mult, reason)
VALUES
('swm_retreat_rumor_bandits', 'scn_retreat_rumor_inn', 1, 'bandits', 4, 1.0, 'Bandit pressure increases rumor scenes');

-- High danger makes escape scenes more dramatic
INSERT OR IGNORE INTO scene_weight_mods
(id, template_id, enabled, min_danger, weight_add, weight_mult, reason)
VALUES
('swm_escape_high_danger', 'scn_escape_river_route', 1, 50, 3, 1.1, 'High danger favors stealthy getaways');


/* =========================================================
   9) App pick pattern (comment)
   =========================================================
   A) candidates:
     SELECT * FROM v_scene_picklist
     WHERE encounter_run_id=? AND character_id=? AND final_weight > 0
     ORDER BY final_weight DESC;

   B) weighted pick:
     - sum(final_weight)
     - roll 1..sum
     - cumulative in app (recommended) then insert into scene_instances
   ========================================================= */

COMMIT;
