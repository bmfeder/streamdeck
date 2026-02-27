// Server-side environment variables (accessed in loaders/actions)
export function getEnv() {
  return {
    SUPABASE_URL: process.env.SUPABASE_URL!,
    SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY!,
    POWERSYNC_URL: process.env.POWERSYNC_URL!,
  };
}

// Client-side env (exposed via root loader)
export type ClientEnv = ReturnType<typeof getEnv>;
