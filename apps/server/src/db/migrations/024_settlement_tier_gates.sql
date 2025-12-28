PRAGMA foreign_keys = ON;
BEGIN;

/* =========================================================
   SETTLEMENT TIER GATES
   Purpose:
     - Gate shop/container stock by settlement tier & prosperity
     - Keep villages from selling full plate + legendary gear
     - Let cities/capitals feel like "the big leagues"

   Tiers (suggested):
     1 = hamlet/outpost
     2 = village
     3 = town
     4 = city
     5 = capital/legendary hub

   Prosperity (0..100):
     0  = starving / war-torn
     50 = normal
     80 = wealthy
     95 = absurdly rich / trade nexus
   ========================================================= */

/* ---------------------------------------------------------
   A) Add tier + prosperity to settlements
   --------------------------------------------------------- */

-- If your settlements_v2 already has a "type" field, keep it.
-- We'll add numeric tier + prosperity so you can gate precisely.
ALTER TABLE settlements_v2 ADD COLUMN tier INTEGER NOT NULL DEFAULT 3;
ALTER TABLE settlements_v2 ADD COLUMN prosperity INTEGER NOT NULL DEFAULT 50;

-- Helpful index for queries and balancing dashboards
CREATE INDEX IF NOT EXISTS idx_settlements_tier_prosperity
ON settlements_v2(tier, prosperity);

/* ---------------------------------------------------------
   B) Add gating columns to container_stock_rules
   --------------------------------------------------------- */

-- These gates control whether a stock rule is eligible.
-- Defaults = allow everywhere, so it won’t break existing content.
ALTER TABLE container_stock_rules ADD COLUMN min_settlement_tier INTEGER NOT NULL DEFAULT 1;
ALTER TABLE container_stock_rules ADD COLUMN max_settlement_tier INTEGER NOT NULL DEFAULT 5;
ALTER TABLE container_stock_rules ADD COLUMN min_prosperity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE container_stock_rules ADD COLUMN max_prosperity INTEGER NOT NULL DEFAULT 100;

-- Optional: gate by settlement "type" (village/town/city) if you prefer
ALTER TABLE container_stock_rules ADD COLUMN settlement_type TEXT NULL;

-- Optional: gate by building/shop type hints if you want later
ALTER TABLE container_stock_rules ADD COLUMN building_type TEXT NULL;

CREATE INDEX IF NOT EXISTS idx_container_stock_gates
ON container_stock_rules(container_def_id, min_settlement_tier, max_settlement_tier, min_prosperity, max_prosperity);

/* ---------------------------------------------------------
   C) View: eligible stock rules for a given settlement + container
   --------------------------------------------------------- */

-- Your engine can do:
-- SELECT * FROM v_container_stock_eligible
--  WHERE settlement_id = 'set_brindlewick'
--    AND container_def_id = 'cdef_smith_armory'
--  ORDER BY weight DESC;

CREATE VIEW IF NOT EXISTS v_container_stock_eligible AS
SELECT
  csr.container_def_id,
  csr.item_def_id,
  csr.min_qty,
  csr.max_qty,
  csr.weight,
  csr.price_mult,
  csr.restock_minutes,
  csr.meta_json,
  s.id AS settlement_id,
  s.name AS settlement_name,
  s.type AS settlement_type_actual,
  s.tier AS settlement_tier,
  s.prosperity AS settlement_prosperity
FROM container_stock_rules csr
JOIN settlements_v2 s
  ON 1=1
WHERE
  s.tier BETWEEN csr.min_settlement_tier AND csr.max_settlement_tier
  AND s.prosperity BETWEEN csr.min_prosperity AND csr.max_prosperity
  AND (csr.settlement_type IS NULL OR csr.settlement_type = s.type);

/* ---------------------------------------------------------
   D) Seed tier defaults (safe + sensible)
   --------------------------------------------------------- */

-- If you already seeded settlements, we can set tier based on s.type.
-- Adjust mapping however you like.
UPDATE settlements_v2
SET tier =
  CASE
    WHEN type IN ('hamlet','outpost') THEN 1
    WHEN type IN ('village')         THEN 2
    WHEN type IN ('town')            THEN 3
    WHEN type IN ('city')            THEN 4
    WHEN type IN ('capital')         THEN 5
    ELSE tier
  END
WHERE tier IS NULL OR tier = 3;

-- Prosperity default already 50, but if you want some flavor:
-- Example: ports and trade towns trend richer (tweak later).
UPDATE settlements_v2
SET prosperity =
  CASE
    WHEN type IN ('capital') THEN 85
    WHEN type IN ('city')    THEN 75
    WHEN type IN ('town')    THEN 55
    WHEN type IN ('village') THEN 45
    WHEN type IN ('hamlet','outpost') THEN 35
    ELSE prosperity
  END
WHERE prosperity IS NULL OR prosperity = 50;

/* ---------------------------------------------------------
   E) Apply gates to your rare/magical stock rules (examples)
   --------------------------------------------------------- */

-- These UPDATEs assume you inserted these exact rules earlier:
-- (cdef_smith_armory, itm_mithral_shirt)
-- (cdef_smith_armory, itm_adamantine_plate)
-- (cdef_smith_armory, itm_sunblade)

-- Mithral: city+ and reasonably prosperous
UPDATE container_stock_rules
SET
  min_settlement_tier = 4,
  max_settlement_tier = 5,
  min_prosperity = 65,
  max_prosperity = 100
WHERE container_def_id = 'cdef_smith_armory'
  AND item_def_id = 'itm_mithral_shirt';

-- Adamantine Plate: capital only, very wealthy
UPDATE container_stock_rules
SET
  min_settlement_tier = 5,
  max_settlement_tier = 5,
  min_prosperity = 85,
  max_prosperity = 100
WHERE container_def_id = 'cdef_smith_armory'
  AND item_def_id = 'itm_adamantine_plate';

-- Sunblade: capital only, very wealthy (or special temple vault later)
UPDATE container_stock_rules
SET
  min_settlement_tier = 5,
  max_settlement_tier = 5,
  min_prosperity = 90,
  max_prosperity = 100
WHERE container_def_id = 'cdef_smith_armory'
  AND item_def_id = 'itm_sunblade';

COMMIT;
