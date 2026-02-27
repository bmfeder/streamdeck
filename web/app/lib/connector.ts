import {
  type AbstractPowerSyncDatabase,
  type PowerSyncBackendConnector,
  UpdateType,
} from "@powersync/web";
import type { SupabaseClient } from "@supabase/supabase-js";

// Tables where we set user_id on insert
const TABLES_WITH_USER_ID = [
  "playlists",
  "channels",
  "vod_items",
  "watch_progress",
  "user_preferences",
];

export class SupabaseConnector implements PowerSyncBackendConnector {
  private supabase: SupabaseClient;
  private powersyncUrl: string;

  constructor(supabase: SupabaseClient, powersyncUrl: string) {
    this.supabase = supabase;
    this.powersyncUrl = powersyncUrl;
  }

  async fetchCredentials() {
    const {
      data: { session },
    } = await this.supabase.auth.getSession();

    if (!session?.access_token) {
      throw new Error("Not authenticated");
    }

    return {
      endpoint: this.powersyncUrl,
      token: session.access_token,
    };
  }

  async uploadData(database: AbstractPowerSyncDatabase) {
    const batch = await database.getCrudBatch(200);
    if (!batch) return;

    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    const userId = user?.id;

    for (const op of batch.crud) {
      const table = op.table;
      const id = op.id;
      const opData = { ...op.opData };

      // Inject user_id for inserts on tables that need it
      if (
        op.op === UpdateType.PUT &&
        TABLES_WITH_USER_ID.includes(table) &&
        userId
      ) {
        opData.user_id = userId;
      }

      switch (op.op) {
        case UpdateType.PUT:
          await this.supabase.from(table).upsert({ id, ...opData });
          break;
        case UpdateType.PATCH:
          await this.supabase.from(table).update(opData).eq("id", id);
          break;
        case UpdateType.DELETE:
          await this.supabase.from(table).delete().eq("id", id);
          break;
      }
    }

    await batch.complete();
  }

  // Expose supabase client for auth operations
  getSupabase() {
    return this.supabase;
  }
}
