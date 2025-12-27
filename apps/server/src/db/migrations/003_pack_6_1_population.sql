PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   PACK 6.1 — Settlement Auto-Population & Density Rules
   ========================================================= */


/* ---------------------------------------------------------
   1) Settlement population targets
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS settlement_population_rules (
  settlement_type TEXT PRIMARY KEY,        -- village/town/city
  min_population INTEGER NOT NULL,
  max_population INTEGER NOT NULL,
  min_children INTEGER NOT NULL,
  max_children INTEGER NOT NULL,
  min_businesses INTEGER NOT NULL,
  max_businesses INTEGER NOT NULL,
  min_events INTEGER NOT NULL,
  max_events INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

INSERT OR IGNORE INTO settlement_population_rules
(settlement_type, min_population, max_population, min_children, max_children,
 min_businesses, max_businesses, min_events, max_events)
VALUES
('village',  18,  35,  3,  8,  4,  7,  2,  4),
('town',     40,  80,  6, 15,  8, 14,  3,  6),
('city',    120, 240, 15, 40, 18, 30,  5, 10);


/* ---------------------------------------------------------
   2) NPC role pools (by business template)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS npc_role_pools (
  id TEXT PRIMARY KEY,             -- rp_blacksmith
  business_template_id TEXT NULL,  -- bt_blacksmith, NULL = roaming
  role TEXT NOT NULL,
  weight INTEGER NOT NULL DEFAULT 10,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (business_template_id)
    REFERENCES business_templates(id) ON DELETE CASCADE
);

INSERT OR IGNORE INTO npc_role_pools
(id, business_template_id, role, weight)
VALUES
-- General store
('rp_gen_merchant','bt_general_store','merchant',30),
('rp_gen_clerk','bt_general_store','clerk',25),
('rp_gen_porter','bt_general_store','porter',15),

-- Smith
('rp_smith_master','bt_blacksmith','blacksmith',25),
('rp_smith_apprentice','bt_blacksmith','apprentice',20),
('rp_smith_merchant','bt_blacksmith','merchant',10),

-- Alchemy
('rp_alch_master','bt_alchemist','alchemist',25),
('rp_alch_herbalist','bt_alchemist','herbalist',20),
('rp_alch_assist','bt_alchemist','assistant',15),

-- Tavern
('rp_tavern_keeper','bt_tavern','innkeeper',25),
('rp_tavern_barkeep','bt_tavern','barkeep',25),
('rp_tavern_server','bt_tavern','server',20),
('rp_tavern_cook','bt_tavern','cook',15),

-- Stables
('rp_stable_master','bt_stables','stablemaster',25),
('rp_stable_hand','bt_stables','handler',20),

-- Temple
('rp_priest','bt_temple','priest',25),
('rp_acolyte','bt_temple','acolyte',20),
('rp_healer','bt_temple','healer',15),

-- Guildhall
('rp_guild_captain','bt_guildhall','captain',20),
('rp_guild_recruiter','bt_guildhall','recruiter',20),
('rp_guild_veteran','bt_guildhall','veteran',20),

-- Roaming roles (no building)
('rp_guard',NULL,'guard',25),
('rp_child',NULL,'child',40),
('rp_laborer',NULL,'laborer',20),
('rp_traveler',NULL,'traveler',15);


/* ---------------------------------------------------------
   3) Personality trait pools (AI-readable)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS npc_personality_pools (
  id TEXT PRIMARY KEY,
  trait_type TEXT NOT NULL,       -- temperament/voice/moral
  value TEXT NOT NULL,
  weight INTEGER NOT NULL DEFAULT 10
);

INSERT OR IGNORE INTO npc_personality_pools
(id, trait_type, value, weight)
VALUES
-- Temperament
('pt_calm','temperament','calm',25),
('pt_steady','temperament','steady',30),
('pt_fiery','temperament','fiery',20),
('pt_goofy','temperament','goofy',15),
('pt_anxious','temperament','anxious',10),

-- Voice
('pv_plain','voice','plain',30),
('pv_gruff','voice','gruff',15),
('pv_cheerful','voice','cheerful',25),
('pv_poetic','voice','poetic',15),
('pv_shy','voice','shy',15),

-- Morals
('pm_good','moral','good',30),
('pm_neutral','moral','neutral',40),
('pm_lawful','moral','lawful',20),
('pm_chaotic','moral','chaotic',10);


/* ---------------------------------------------------------
   4) Name pools (kid-safe, expandable)
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS npc_name_pools (
  id TEXT PRIMARY KEY,
  age_group TEXT NOT NULL,     -- child/teen/adult/elder
  name TEXT NOT NULL,
  weight INTEGER NOT NULL DEFAULT 10
);

INSERT OR IGNORE INTO npc_name_pools
(id, age_group, name, weight)
VALUES
-- =========================================================
-- 0) Children
-- =========================================================
('nm_child_finn',  'child', 'Finn',  15),
('nm_child_kiki',  'child', 'Kiki',  15),
('nm_child_toby',  'child', 'Toby',  15),
('nm_child_fern',  'child', 'Fern',  10),
('nm_child_jax',   'child', 'Jax',   10),
('nm_child_mia',   'child', 'Mia',   15),
('nm_child_nico',  'child', 'Nico',  10),
('nm_child_wren',  'child', 'Wren',  10),
('nm_child_olly',  'child', 'Olly',  15),
('nm_child_zora',  'child', 'Zora',  10),

-- =========================================================
-- 1) Teens
-- =========================================================
('nm_teen_kael',   'teen',  'Kael',  20),
('nm_teen_lyra',   'teen',  'Lyra',  20),
('nm_teen_valen',  'teen',  'Valen', 15),
('nm_teen_jace',   'teen',  'Jace',  15),
('nm_teen_veda',   'teen',  'Veda',  15),
('nm_teen_silas',  'teen',  'Silas', 10),
('nm_teen_kestrel', 'teen', 'Kestrel', 15),
('nm_teen_zale',    'teen', 'Zale',    15),
('nm_teen_sora',    'teen', 'Sora',    20),
('nm_teen_vesper',  'teen', 'Vesper',  10),
('nm_teen_lark',    'teen', 'Lark',    15),
('nm_teen_talon',   'teen', 'Talon',   10),
('nm_teen_brinn',   'teen', 'Brinn',   20),
('nm_teen_nyx',     'teen', 'Nyx',     10),
('nm_teen_elias',   'teen', 'Elias',   15),
('nm_teen_koda',    'teen', 'Koda',    15),

-- =========================================================
-- 2) Adults
-- =========================================================
('nm_adult_brom',    'adult', 'Brom',    20),
('nm_adult_elara',   'adult', 'Elara',   20),
('nm_adult_kaelen',  'adult', 'Kaelen',  15),
('nm_adult_thistle', 'adult', 'Thistle', 10),
('nm_adult_rowan',   'adult', 'Rowan',   15),
('nm_adult_maren',   'adult', 'Maren',   15),
('nm_adult_torin',   'adult', 'Torin',   15),
('nm_adult_runa',    'adult', 'Runa',    15),
('nm_adult_fletcher','adult', 'Fletcher',10),
('nm_adult_belen',   'adult', 'Belen',   10),

-- =========================================================
-- 3) Elders
-- =========================================================
('nm_elder_hagar',   'elder', 'Hagar',   20),
('nm_elder_muriel',  'elder', 'Muriel',  20),
('nm_elder_eustace', 'elder', 'Eustace', 15),
('nm_elder_grizelda','elder', 'Grizelda',10),
('nm_elder_olin',    'elder', 'Olin',    15),
('nm_elder_verna',   'elder', 'Verna',   15);


/* ---------------------------------------------------------
   5) Event density rules
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS settlement_event_rules (
  settlement_type TEXT PRIMARY KEY,
  weekly_events INTEGER NOT NULL,
  seasonal_events INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}'
);

INSERT OR IGNORE INTO settlement_event_rules
(settlement_type, weekly_events, seasonal_events)
VALUES
('village', 2, 1),
('town',    3, 2),
('city',    5, 3);


/* ---------------------------------------------------------
   6) Population planning snapshot (engine-written)
   --------------------------------------------------------- */
-- This table is filled by your engine/script AFTER reading the rules above.
-- It lets you persist the generated plan so towns are stable across saves.
CREATE TABLE IF NOT EXISTS settlement_population_plan (
  settlement_id TEXT PRIMARY KEY,
  planned_population INTEGER NOT NULL,
  planned_children INTEGER NOT NULL,
  planned_businesses INTEGER NOT NULL,
  planned_events INTEGER NOT NULL,
  seed INTEGER NOT NULL,
  generated_at INTEGER NOT NULL,
  meta_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (settlement_id)
    REFERENCES settlements_v2(id) ON DELETE CASCADE
);

COMMIT;
