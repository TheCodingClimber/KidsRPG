// apps/server/src/http.ts
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

  function tableExists(db: any, tableName: string): boolean {
  const row = db
    .prepare(
      `SELECT name
       FROM sqlite_master
       WHERE type='table' AND name = ?`
    )
    .get(tableName) as { name: string } | undefined;

  return !!row;
}

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
     Character Creation / Listing
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

  // Delete a character (and cascade deletes saves/equipment/items via foreign keys)
  app.delete("/characters/:characterId", requireAuth, (req, res) => {
    const { accountId } = req as AuthedRequest;
    const { characterId } = req.params;

    const db = openDb();

    const row = db
      .prepare(`SELECT id FROM characters WHERE id = ? AND account_id = ?`)
      .get(characterId, accountId) as { id: string } | undefined;

    if (!row) {
      db.close();
      return res.status(404).json({ error: "Character not found" });
    }

    db.prepare(`DELETE FROM characters WHERE id = ? AND account_id = ?`).run(
      characterId,
      accountId
    );

    db.close();
    res.json({ ok: true });
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

    // Optional: unique name per account
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

  app.get("/game/load/:characterId", requireAuth, (req, res) => {
    const { accountId } = req as AuthedRequest;
    const { characterId } = req.params;

    const db = openDb();

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

  /* =========================
     Fast Travel (DB settlements source of truth)
     ========================= */
  const FastTravelSchema = z.object({
    regionId: z.string().min(1),
    settlementId: z.string().min(1),
  });

  app.post("/game/fast-travel/:characterId", requireAuth, (req, res) => {
    const { accountId } = req as AuthedRequest;
    const { characterId } = req.params;

    const parsed = FastTravelSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: parsed.error.message });
    }

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

    // Load settlement from DB (source of truth)
    const row = db
      .prepare(
        `SELECT id, name, type, x, y, meta_json
         FROM settlements_v2
         WHERE id = ? AND region_id = ?`
      )
      .get(settlementId, regionId) as
      | { id: string; name: string; type: string; x: number; y: number; meta_json: string }
      | undefined;

    if (!row) {
      db.close();
      return res.status(404).json({ error: "Settlement not found" });
    }

    let meta: any = {};
    try {
      meta = row.meta_json ? JSON.parse(row.meta_json) : {};
    } catch {
      meta = {};
    }

    const settlement = {
      id: row.id,
      name: row.name,
      type: row.type,
      x: Number(row.x),
      y: Number(row.y),
      signpost: meta?.signpost,
      travelFee: meta?.travelFee,
    };

    const fee = Number(
      settlement.travelFee ??
        (settlement.type === "capital"
          ? 60
          : settlement.type === "city"
            ? 40
            : settlement.type === "town"
              ? 25
              : 10)
    );

    if (char.gold < fee) {
      db.close();
      return res.status(400).json({ error: `Not enough gold. Need ${fee}g.` });
    }

    const now = Date.now();

    // Deduct gold
    db.prepare(`UPDATE characters SET gold = gold - ?, updated_at = ? WHERE id = ?`)
      .run(fee, now, characterId);

    // Destination: signpost if present, else settlement coords
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

    const updatedChar = db
      .prepare(`SELECT id, gold FROM characters WHERE id = ?`)
      .get(characterId);

    const save = db
      .prepare(`SELECT region_id, x, y, last_seen_at, state_json FROM saves WHERE character_id = ?`)
      .get(characterId);

    db.close();

    return res.json({
      ok: true,
      fee,
      character: updatedChar,
      save,
      settlementName: settlement.name,
    });
  });

  /* =========================
     World: Regions (JSON tiles + DB settlements)
     ========================= */
  app.get("/world/regions/:regionId", requireAuth, (req, res) => {
    const { regionId } = req.params;

    try {
      const worldPath = path.resolve(
        process.cwd(),
        "../../data/world",
        `${regionId}_v1.json`
      );

      if (!fs.existsSync(worldPath)) {
        return res.status(404).json({ error: "Region not found" });
      }

      // 1) Load tiles/legend/POIs from JSON (render cache)
      const raw = fs.readFileSync(worldPath, "utf-8");
      const world = JSON.parse(raw);

      // 2) Load settlements from DB (source of truth)
      const db = openDb();
      const rows = db
        .prepare(
          `SELECT id, name, type, x, y, meta_json, tier, prosperity
           FROM settlements_v2
           WHERE region_id = ?
           ORDER BY name ASC`
        )
        .all(regionId) as Array<{
          id: string;
          name: string;
          type: string;
          x: number;
          y: number;
          meta_json: string;
          tier?: number;
          prosperity?: number;
        }>;

      db.close();

      const settlements = rows.map((r) => {
        let meta: any = {};
        try {
          meta = r.meta_json ? JSON.parse(r.meta_json) : {};
        } catch {
          meta = {};
        }

        return {
          id: r.id,
          name: r.name,
          type: r.type,
          x: Number(r.x),
          y: Number(r.y),
          signpost: meta?.signpost,
          travelFee: meta?.travelFee,
          tier: typeof r.tier === "number" ? r.tier : undefined,
          prosperity: typeof r.prosperity === "number" ? r.prosperity : undefined,
        };
      });

      world.settlements = settlements;
      world._sources = { tiles: "json", settlements: "db" };
      // 3) Load POIs from DB (source of truth)
const poiRows = db
  .prepare(
    `SELECT id, name, type, x, y, min_level, meta_json
     FROM pois_v1
     WHERE region_id = ?
     ORDER BY min_level ASC, name ASC`
  )
  .all(regionId) as Array<{
    id: string;
    name: string;
    type: string;
    x: number;
    y: number;
    min_level: number;
    meta_json: string;
  }>;

  const pointsOfInterest = poiRows.map((p) => {
    let meta: any = {};
    try { meta = p.meta_json ? JSON.parse(p.meta_json) : {}; } catch { meta = {}; }
    return {
      id: p.id,
      name: p.name,
      type: p.type,
      x: Number(p.x),
      y: Number(p.y),
      minLevel: Number(p.min_level),
      ...meta, // optional fields like note
    };
  });

world.pointsOfInterest = pointsOfInterest;
      return res.json(world);
    } catch (err) {
      console.error("Failed to load world:", err);
      return res.status(500).json({ error: "Failed to load world" });
    }
  });

  return app;
}
