import { PowerSyncDatabase } from "@powersync/web";
import { AppSchema } from "./powersync-schema";
import { SupabaseConnector } from "./connector";
import { getSupabaseBrowserClient } from "./supabase.client";
import type { ClientEnv } from "./env";

let db: PowerSyncDatabase | null = null;
let connectionPromise: Promise<void> | null = null;

export function getPowerSync(env: ClientEnv) {
  if (!db) {
    db = new PowerSyncDatabase({
      schema: AppSchema,
      database: { dbFilename: "streamdeck.db" },
    });
  }
  return db;
}

export async function connectPowerSync(env: ClientEnv) {
  if (connectionPromise) return connectionPromise;

  connectionPromise = (async () => {
    const ps = getPowerSync(env);
    const supabase = getSupabaseBrowserClient(env);
    const connector = new SupabaseConnector(supabase, env.POWERSYNC_URL);
    await ps.connect(connector);
  })();

  return connectionPromise;
}

export async function disconnectPowerSync() {
  if (db) {
    await db.disconnect();
    connectionPromise = null;
  }
}
