import crypto from "node:crypto";
import { openDb } from "../db/db.js";

export function newId(prefix: string) {
  return `${prefix}_${crypto.randomBytes(16).toString("hex")}`;
}

export function createSession(accountId: string, hours = 24 * 30) {
  const db = openDb();
  const id = newId("sess");
  const now = Date.now();
  const expiresAt = now + hours * 60 * 60 * 1000;

  db.prepare(
    `INSERT INTO sessions (id, account_id, created_at, expires_at)
     VALUES (?, ?, ?, ?)`
  ).run(id, accountId, now, expiresAt);

  db.close();
  return { id, expiresAt };
}

export function getSession(sessionId: string) {
  const db = openDb();
  const row = db
    .prepare(`SELECT id, account_id, expires_at FROM sessions WHERE id = ?`)
    .get(sessionId) as { id: string; account_id: string; expires_at: number } | undefined;
  db.close();

  if (!row) return null;
  if (row.expires_at < Date.now()) return null;
  return { id: row.id, accountId: row.account_id };
}
