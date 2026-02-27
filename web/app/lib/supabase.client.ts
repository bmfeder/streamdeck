import { createBrowserClient } from "@supabase/ssr";
import type { ClientEnv } from "./env";

let client: ReturnType<typeof createBrowserClient> | null = null;

export function getSupabaseBrowserClient(env: ClientEnv) {
  if (client) return client;
  client = createBrowserClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);
  return client;
}
