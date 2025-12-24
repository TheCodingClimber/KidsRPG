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
    console.log("Applying", f);
    const sql = fs.readFileSync(full, "utf8");
    db.exec(sql);
  }

  db.close();
  console.log("Migrations complete.");
}

main();
