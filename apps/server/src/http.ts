import express from "express";
import cors from "cors";
import crypto from "node:crypto";
import { z } from "zod";
import fs from "node:fs";
import path from "node:path";
import { openDb } from "./db/db.js";
import { hashPin, verifyPin } from "./auth/pin.js";
import { createSession } from "./auth/sessions.js";
import { requireAuth, type AuthedRequest } from "./auth/requireAuth.js";

export function createHttpServer() {
  const app = express();

  app.use(cors());
  app.use(express.json());

  /* =========================
     Health
     ========================= */
  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });

  /* =========================
     Auth: Register / Login
     ========================= */
  app.post("/auth/register", async (req, res) => {
    const { name, pin } = req.body ?? {};

    if (!name || !pin || String(pin).length < 4) {
      return res.status(400).json({ error: "Name and 4+ digit PIN required" });
    }

    const db = openDb();
    const exists = db.prepare(`SELECT id FROM accounts WHERE name = ?`).get(name);

    if (exists) {
      db.close();
      return res.status(409).json({ error: "Account already exists" });
    }

    const id = `acct_${crypto.randomBytes(16).toString("hex")}`;
    const pin_hash = await hashPin(String(pin));
    const now = Date.now();

    db.prepare(
      `INSERT INTO accounts (id, name, pin_hash, created_at)
       VALUES (?, ?, ?, ?)`
    ).run(id, name, pin_hash, now);

    db.close();

    const session = createSession(id);
    res.json({
      accountId: id,
      sessionId: session.id,
      expiresAt: session.expiresAt,
    });
  });

  app.post("/auth/login", async (req, res) => {
    const { name, pin } = req.body ?? {};
    if (!name || !pin) {
      return res.status(400).json({ error: "Name and PIN required" });
    }

    const db = openDb();
    const row = db
      .prepare(`SELECT id, pin_hash FROM accounts WHERE name = ?`)
      .get(name) as { id: string; pin_hash: string } | undefined;
    db.close();

    if (!row) {
      return res.status(404).json({ error: "Account not found" });
    }

    const ok = await verifyPin(String(pin), row.pin_hash);
    if (!ok) {
      return res.status(401).json({ error: "Wrong PIN" });
    }

    const session = createSession(row.id);
    res.json({
      accountId: row.id,
      sessionId: session.id,
      expiresAt: session.expiresAt,
    });
  });

  /* =========================
     Character Creation
     ========================= */
  const CreateCharSchema = z.object({
    name: z.string().min(1).max(24),
    race: z.string().min(1).max(24),
    class: z.string().min(1).max(24),
    background: z.string().min(1).max(32),
    personality: z.number().int().min(0).max(100),
    starterKitId: z.string().min(1).max(32),
  });

  app.get("/characters", requireAuth, (req, res) => {
    const { accountId } = req as AuthedRequest;
    const db = openDb();

    // Delete a character (and cascade deletes saves/equipment/items via foreign keys)
app.delete("/characters/:characterId", requireAuth, (req, res) => {
  const { accountId } = req as AuthedRequest;
  const { characterId } = req.params;

  const db = openDb();

  // Verify character belongs to this account
  const row = db
    .prepare(`SELECT id FROM characters WHERE id = ? AND account_id = ?`)
    .get(characterId, accountId) as { id: string } | undefined;

  if (!row) {
    db.close();
    return res.status(404).json({ error: "Character not found" });
  }

  db.prepare(`DELETE FROM characters WHERE id = ? AND account_id = ?`).run(characterId, accountId);

  db.close();
  res.json({ ok: true });
});


    const rows = db
      .prepare(
        `SELECT id, name, race, class, background, personality, level, gold
         FROM characters
         WHERE account_id = ?
         ORDER BY created_at DESC`
      )
      .all(accountId);

    db.close();
    res.json({ characters: rows });
  });

  /* =========================
   Inventory (Backpack) - using existing items/equipment tables
   ========================= */

app.get("/inventory/:characterId", requireAuth, (req, res) => {
  const { accountId } = req as AuthedRequest;
  const { characterId } = req.params;

  const db = openDb();

  // Ensure character belongs to account
  const ok = db
    .prepare(`SELECT id FROM characters WHERE id = ? AND account_id = ?`)
    .get(characterId, accountId);

  if (!ok) {
    db.close();
    return res.status(404).json({ error: "Character not found" });
  }

  // Return items NOT currently equipped
  const rows = db
    .prepare(
      `SELECT id as itemId, name, slot, rarity, stats_json as statsJson
       FROM items
       WHERE character_id = ?
         AND id NOT IN (
           SELECT item_id FROM equipment
           WHERE character_id = ?
             AND item_id IS NOT NULL
         )
       ORDER BY name ASC`
    )
    .all(characterId, characterId);

  db.close();
  res.json({ items: rows });
});

app.post("/inventory/drop/:characterId", requireAuth, (req, res) => {
  const { accountId } = req as AuthedRequest;
  const { characterId } = req.params;

  const DropSchema = z.object({
    itemId: z.string().min(1),
  });

  const parsed = DropSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.message });
  }

  const { itemId } = parsed.data;

  const db = openDb();

  // Ensure character belongs to account
  const ok = db
    .prepare(`SELECT id FROM characters WHERE id = ? AND account_id = ?`)
    .get(characterId, accountId);

  if (!ok) {
    db.close();
    return res.status(404).json({ error: "Character not found" });
  }

  // If this item is equipped, unequip it first
  db.prepare(
    `UPDATE equipment
     SET item_id = NULL
     WHERE character_id = ? AND item_id = ?`
  ).run(characterId, itemId);

  // Delete the item (only if it belongs to this character)
  const result = db
    .prepare(`DELETE FROM items WHERE id = ? AND character_id = ?`)
    .run(itemId, characterId);

  db.close();

  res.json({ ok: true, deleted: result.changes });
});


  app.post("/characters", requireAuth, (req, res) => {
    const { accountId } = req as AuthedRequest;
    const parsed = CreateCharSchema.safeParse(req.body);

    if (!parsed.success) {
      return res.status(400).json({ error: parsed.error.message });
    }

    const db = openDb();
    const id = `char_${crypto.randomBytes(16).toString("hex")}`;
    const now = Date.now();

    const { name, race, class: cls, background, personality, starterKitId } =
      parsed.data;

    // optional: unique name per account
    const exists = db
      .prepare(`SELECT id FROM characters WHERE account_id = ? AND name = ?`)
      .get(accountId, name);

    if (exists) {
      db.close();
      return res.status(409).json({ error: "Character name already exists" });
    }

    db.prepare(
      `INSERT INTO characters
       (id, account_id, name, race, class, background, personality,
        level, gold, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?)`
    ).run(id, accountId, name, race, cls, background, personality, now, now);

    // Save initial state (includes starter kit selection)
    const state = JSON.stringify({ starterKitId });

    // Spawn at Brindlewick signpost (20,18) in hearthlands
    db.prepare(
      `INSERT INTO saves (character_id, region_id, x, y, last_seen_at, state_json)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).run(id, "hearthlands", 20, 18, now, state);

    // Initialize equipment slots (forgiving but enforced)
    const slots = [
      "helmet",
      "torso",
      "gloves",
      "legs",
      "boots",
      "ring1",
      "ring2",
      "amulet",
      "cloak",
      "trinket",
    ];

    const stmt = db.prepare(
      `INSERT INTO equipment (character_id, slot, item_id)
       VALUES (?, ?, NULL)`
    );

    for (const slot of slots) {
      stmt.run(id, slot);
    }

    db.close();
    res.json({ characterId: id });
  });

  /* =========================
     Load / Save Game
     ========================= */
  const SavePosSchema = z.object({
    regionId: z.string().min(1),
    x: z.number().int(),
    y: z.number().int(),
  });

  /* =========================
   Inventory (Backpack)
   ========================= */

// Returns backpack items for a character (owned by this account)
app.get("/inventory/:characterId", requireAuth, (req, res) => {
  const { accountId } = req as AuthedRequest;
  const { characterId } = req.params;

  const db = openDb();

  // Ensure character belongs to account
  const ok = db
    .prepare(`SELECT id FROM characters WHERE id = ? AND account_id = ?`)
    .get(characterId, accountId);

  if (!ok) {
    db.close();
    return res.status(404).json({ error: "Character not found" });
  }

  // Try to load from a real inventory table if it exists.
  // If your schema differs, adjust the query to match.
  // Expected schema: inventory(character_id, item_id, qty) + items(id, name)
  try {
    const rows = db
      .prepare(
        `SELECT i.id as itemId, i.name as name, COALESCE(inv.qty, 1) as qty
         FROM inventory inv
         JOIN items i ON i.id = inv.item_id
         WHERE inv.character_id = ?
         ORDER BY i.name ASC`
      )
      .all(characterId) as Array<{ itemId: string; name: string; qty: number }>;

    db.close();
    return res.json({ items: rows });
  } catch (err) {
    // If the inventory table doesn't exist yet, return empty backpack instead of crashing.
    db.close();
    return res.json({ items: [] });
  }
});

// Drops ONE unit of an item (or removes the row if qty hits 0)
app.post("/inventory/drop/:characterId", requireAuth, (req, res) => {
  const { accountId } = req as AuthedRequest;
  const { characterId } = req.params;

  const ItemDropSchema = z.object({
    itemId: z.string().min(1),
  });

  const parsed = ItemDropSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.message });
  }

  const { itemId } = parsed.data;

  const db = openDb();

  // Ensure character belongs to account
  const ok = db
    .prepare(`SELECT id FROM characters WHERE id = ? AND account_id = ?`)
    .get(characterId, accountId);

  if (!ok) {
    db.close();
    return res.status(404).json({ error: "Character not found" });
  }

  // If inventory table isn't present, treat as no-op
  try {
    const row = db
      .prepare(`SELECT qty FROM inventory WHERE character_id = ? AND item_id = ?`)
      .get(characterId, itemId) as { qty: number } | undefined;

    if (!row) {
      db.close();
      return res.json({ ok: true });
    }

    if (row.qty <= 1) {
      db.prepare(`DELETE FROM inventory WHERE character_id = ? AND item_id = ?`).run(characterId, itemId);
    } else {
      db.prepare(
        `UPDATE inventory SET qty = qty - 1 WHERE character_id = ? AND item_id = ?`
      ).run(characterId, itemId);
    }

    db.close();
    return res.json({ ok: true });
  } catch {
    db.close();
    return res.json({ ok: true });
  }
});


  app.get("/game/load/:characterId", requireAuth, (req, res) => {
    const { accountId } = req as AuthedRequest;
    const { characterId } = req.params;

    const db = openDb();

const FastTravelSchema = z.object({
  regionId: z.string().min(1),
  settlementId: z.string().min(1),
});

function loadWorld(regionId: string) {
  const worldPath = path.resolve(process.cwd(), "../../data/world", `${regionId}_v1.json`);
  const raw = fs.readFileSync(worldPath, "utf-8");
  return JSON.parse(raw);
}

app.post("/game/fast-travel/:characterId", requireAuth, (req, res) => {
  const { accountId } = req as AuthedRequest;
  const { characterId } = req.params;

  const parsed = FastTravelSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.message });

  const { regionId, settlementId } = parsed.data;

  const db = openDb();

  // Verify character belongs to account + get current gold
  const char = db
    .prepare(`SELECT id, gold FROM characters WHERE id = ? AND account_id = ?`)
    .get(characterId, accountId) as { id: string; gold: number } | undefined;

  if (!char) {
    db.close();
    return res.status(404).json({ error: "Character not found" });
  }

  // Load world and find settlement
  let world: any;
  try {
    world = loadWorld(regionId);
  } catch {
    db.close();
    return res.status(404).json({ error: "Region not found" });
  }

  const settlement = (world.settlements || []).find((s: any) => s.id === settlementId);
  if (!settlement) {
    db.close();
    return res.status(404).json({ error: "Settlement not found" });
  }

  const fee = Number(settlement.travelFee ?? (settlement.type === "town" ? 25 : 10));
  if (char.gold < fee) {
    db.close();
    return res.status(400).json({ error: `Not enough gold. Need ${fee}g.` });
  }

  const now = Date.now();

  // Deduct gold
  db.prepare(`UPDATE characters SET gold = gold - ?, updated_at = ? WHERE id = ?`).run(fee, now, characterId);

  // Travel destination: signpost if present, else settlement coords
  const destX = settlement.signpost?.x ?? settlement.x;
  const destY = settlement.signpost?.y ?? settlement.y;

  // Save position (UPSERT)
  db.prepare(
    `INSERT INTO saves (character_id, region_id, x, y, last_seen_at, state_json)
     VALUES (?, ?, ?, ?, ?, '{}')
     ON CONFLICT(character_id) DO UPDATE SET
       region_id = excluded.region_id,
       x = excluded.x,
       y = excluded.y,
       last_seen_at = excluded.last_seen_at`
  ).run(characterId, regionId, destX, destY, now);

  // Return updated state
    const updatedChar = db
        .prepare(`SELECT id, gold FROM characters WHERE id = ?`)
        .get(characterId);

    const save = db
        .prepare(`SELECT region_id, x, y, last_seen_at, state_json FROM saves WHERE character_id = ?`)
        .get(characterId);

    db.close();
        res.json({ ok: true, fee, character: updatedChar, save, settlementName: settlement.name });
    });


    const character = db
      .prepare(
        `SELECT id, name, race, class, background, personality, level, gold
         FROM characters
         WHERE id = ? AND account_id = ?`
      )
      .get(characterId, accountId);

    if (!character) {
      db.close();
      return res.status(404).json({ error: "Character not found" });
    }

    const save = db
      .prepare(
        `SELECT region_id, x, y, last_seen_at, state_json
         FROM saves
         WHERE character_id = ?`
      )
      .get(characterId);

    db.close();
    res.json({ character, save });
  });

  app.post("/game/save-position/:characterId", requireAuth, (req, res) => {
    const { accountId } = req as AuthedRequest;
    const { characterId } = req.params;

    const parsed = SavePosSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: parsed.error.message });
    }

    const db = openDb();

    // ensure character belongs to account
    const ok = db
      .prepare(`SELECT id FROM characters WHERE id = ? AND account_id = ?`)
      .get(characterId, accountId);

    if (!ok) {
      db.close();
      return res.status(404).json({ error: "Character not found" });
    }

    const now = Date.now();
    const { regionId, x, y } = parsed.data;

    // UPSERT: one canonical save row per character
    // NOTE: We do not update state_json here (so starterKitId stays intact)
    db.prepare(
      `INSERT INTO saves (character_id, region_id, x, y, last_seen_at, state_json)
       VALUES (?, ?, ?, ?, ?, '{}')
       ON CONFLICT(character_id) DO UPDATE SET
         region_id = excluded.region_id,
         x = excluded.x,
         y = excluded.y,
         last_seen_at = excluded.last_seen_at`
    ).run(characterId, regionId, x, y, now);

    db.close();
    res.json({ ok: true });
  });

  /* =========================
     World: Regions
     ========================= */
  app.get("/world/regions/:regionId", requireAuth, (req, res) => {
    const { regionId } = req.params;

    try {
      // process.cwd() will be apps/server when running from that folder
      // ../../data/world -> KidsRPG/data/world
      const worldPath = path.resolve(
        process.cwd(),
        "../../data/world",
        `${regionId}_v1.json`
      );

      if (!fs.existsSync(worldPath)) {
        return res.status(404).json({ error: "Region not found" });
      }

      const raw = fs.readFileSync(worldPath, "utf-8");
      const world = JSON.parse(raw);

      res.json(world);
    } catch (err) {
      console.error("Failed to load world:", err);
      res.status(500).json({ error: "Failed to load world" });
    }
  });

  return app;
}
