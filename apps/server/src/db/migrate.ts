import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DB_PATH, openDb } from "./db.js";

process.on("uncaughtException", (err) => {
  console.error("UNCAUGHT EXCEPTION:", err);
  if (err instanceof Error) console.error(err.stack);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  console.error("UNHANDLED REJECTION:", reason);
  process.exit(1);
});

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function containsTransaction(sql: string) {
  const s = sql.toUpperCase();
  // crude but effective: catches BEGIN, BEGIN TRANSACTION, COMMIT, ROLLBACK
  return (
    /\bBEGIN\b/.test(s) ||
    /\bCOMMIT\b/.test(s) ||
    /\bROLLBACK\b/.test(s)
  );
}

function printFkCheck(db: any) {
  try {
    const rows = db.prepare("PRAGMA foreign_key_check;").all();
    if (!rows.length) {
      console.log("foreign_key_check: no violations found.");
      return;
    }
    console.error("foreign_key_check violations:");
    for (const r of rows.slice(0, 25)) {
      console.error(`- table=${r.table} rowid=${r.rowid} parent=${r.parent} fkid=${r.fkid}`);
    }
    if (rows.length > 25) console.error(`...and ${rows.length - 25} more`);
  } catch (e) {
    console.error("Could not run PRAGMA foreign_key_check:", e);
  }
}

function main() {
  console.log("DB_PATH =", DB_PATH);

  const db = openDb();
  console.log("Opened DB OK");

  const migrationsDir = path.resolve(__dirname, "migrations");
  if (!fs.existsSync(migrationsDir)) {
    throw new Error(`Migrations folder not found: ${migrationsDir}`);
  }

  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  if (files.length === 0) {
    console.log("No migrations found. Nothing to do.");
    db.close();
    return;
  }

  for (const f of files) {
    const full = path.join(migrationsDir, f);
    const sql = fs.readFileSync(full, "utf8");
    const hasTx = containsTransaction(sql);

    console.log("Applying", f, hasTx ? "(file manages its own transaction)" : "");

    try {
      if (!hasTx) {
        db.exec("BEGIN;");
        db.exec("PRAGMA defer_foreign_keys = ON;");
      }

      db.exec(sql);

      if (!hasTx) {
        db.exec("COMMIT;");
      }
    } catch (err) {
      try {
        if (!hasTx) db.exec("ROLLBACK;");
      } catch {}

      console.error(`❌ Migration failed: ${f}`);
      console.error(err);

      printFkCheck(db);

      db.close();
      process.exit(1);
    }
  }

  db.close();
  console.log("✅ Migrations complete.");
}

main();
