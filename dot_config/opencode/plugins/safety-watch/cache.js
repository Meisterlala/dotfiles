import { Database } from "bun:sqlite";
import { mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

function cachePath() {
  const stateHome = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
  return join(stateHome, "opencode", "safety-watch-cache.sqlite");
}

export function createApprovalCache() {
  let databasePromise;

  async function getDatabase() {
    databasePromise ??= (async () => {
      const path = cachePath();
      await mkdir(dirname(path), { recursive: true });
      const database = new Database(path);
      database.exec("PRAGMA journal_mode = WAL");
      database.exec("PRAGMA busy_timeout = 5000");
      database.exec(`
        CREATE TABLE IF NOT EXISTS approved_tool_calls (
          tool_call TEXT PRIMARY KEY
        )
      `);
      return database;
    })();
    try {
      return await databasePromise;
    } catch (error) {
      databasePromise = undefined;
      throw error;
    }
  }

  function toolCall(tool, args) {
    if (tool === "bash" && typeof args?.command === "string")
      return JSON.stringify({ tool, command: args.command });
    return JSON.stringify({ tool, args });
  }

  return {
    async has(tool, args) {
      try {
        const db = await getDatabase();
        return Boolean(
          db
            .query("SELECT 1 FROM approved_tool_calls WHERE tool_call = ?")
            .get(toolCall(tool, args)),
        );
      } catch {
        // A cache failure must fall through to a fresh AI review.
        return false;
      }
    },
    async add(tool, args) {
      try {
        const db = await getDatabase();
        db.query("INSERT OR IGNORE INTO approved_tool_calls (tool_call) VALUES (?)").run(
          toolCall(tool, args),
        );
      } catch {
        // The command was reviewed already; only its cache entry was lost.
      }
    },
  };
}
