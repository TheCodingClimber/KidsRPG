import path from "node:path";
import fs from "node:fs";
import Database from "better-sqlite3";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Always resolves to KidsRPG/data/sqlite/game.sqlite
export const DB_PATH = path.resolve(
  __dirname,
  "../../../../data/sqlite/game.sqlite"
);

function ensureDir(filePath: string) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

export function openDb() {
  ensureDir(DB_PATH);
  const db = new Database(DB_PATH);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  return db;
}
