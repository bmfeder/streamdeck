import { useState, useEffect } from "react";
import { redirect } from "react-router";
import { Settings, Save, Check } from "lucide-react";
import type { Route } from "./+types/dashboard.settings";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { useQuery } from "~/hooks/use-query";
import { usePowerSync } from "~/lib/powersync-provider";
import { cn } from "~/lib/utils";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");

  const { data: prefs } = await supabase
    .from("user_preferences")
    .select("*")
    .single();

  return {
    preferences: prefs ?? {
      preferred_engine: "auto",
      resume_playback_enabled: true,
      buffer_timeout_seconds: 10,
    },
    userEmail: user.email,
  };
}

interface Preferences {
  preferred_engine: string;
  resume_playback_enabled: number;
  buffer_timeout_seconds: number;
}

export default function SettingsPage({ loaderData }: Route.ComponentProps) {
  const db = usePowerSync();

  const { data: livePrefs } = useQuery<Preferences>(
    "SELECT * FROM user_preferences LIMIT 1"
  );
  const prefs = livePrefs[0] ?? (loaderData.preferences as Preferences);

  const [engine, setEngine] = useState(prefs.preferred_engine || "auto");
  const [resume, setResume] = useState(
    typeof prefs.resume_playback_enabled === "number"
      ? !!prefs.resume_playback_enabled
      : prefs.resume_playback_enabled !== false
  );
  const [bufferTimeout, setBufferTimeout] = useState(prefs.buffer_timeout_seconds || 10);
  const [saved, setSaved] = useState(false);

  // Sync form state when live data updates
  useEffect(() => {
    if (livePrefs[0]) {
      setEngine(livePrefs[0].preferred_engine || "auto");
      setResume(!!livePrefs[0].resume_playback_enabled);
      setBufferTimeout(livePrefs[0].buffer_timeout_seconds || 10);
    }
  }, [livePrefs]);

  const handleSave = async () => {
    if (!db) return;

    // Upsert preferences
    const existing = await db.getAll("SELECT * FROM user_preferences LIMIT 1");
    const now = new Date().toISOString();

    if (existing.length > 0) {
      await db.execute(
        "UPDATE user_preferences SET preferred_engine = ?, resume_playback_enabled = ?, buffer_timeout_seconds = ?, updated_at = ? WHERE id = ?",
        [engine, resume ? 1 : 0, bufferTimeout, now, (existing[0] as any).id]
      );
    } else {
      await db.execute(
        "INSERT INTO user_preferences (id, preferred_engine, resume_playback_enabled, buffer_timeout_seconds, updated_at) VALUES (?, ?, ?, ?, ?)",
        [crypto.randomUUID(), engine, resume ? 1 : 0, bufferTimeout, now]
      );
    }

    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  return (
    <div className="max-w-2xl">
      <div className="mb-6">
        <h1 className="text-2xl font-bold">Settings</h1>
        <p className="mt-1 text-sm text-text-secondary">
          Manage your preferences and account
        </p>
      </div>

      {/* Account */}
      <section className="mb-8">
        <h2 className="mb-4 text-lg font-semibold">Account</h2>
        <div className="rounded-xl border border-border bg-surface-raised p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium">Email</p>
              <p className="text-sm text-text-secondary">
                {loaderData.userEmail}
              </p>
            </div>
            <span className="rounded-md bg-accent/10 px-2 py-1 text-xs font-medium text-accent">
              Apple ID
            </span>
          </div>
        </div>
      </section>

      {/* Playback */}
      <section className="mb-8">
        <h2 className="mb-4 text-lg font-semibold">Playback</h2>
        <div className="space-y-4 rounded-xl border border-border bg-surface-raised p-4">
          {/* Player engine */}
          <div>
            <label className="mb-2 block text-sm font-medium">
              Player Engine
            </label>
            <div className="flex gap-2">
              {["auto", "avplayer", "vlckit"].map((opt) => (
                <button
                  key={opt}
                  onClick={() => setEngine(opt)}
                  className={cn(
                    "rounded-lg px-4 py-2 text-sm font-medium transition-colors",
                    engine === opt
                      ? "bg-accent text-surface"
                      : "bg-surface-overlay text-text-secondary hover:text-text-primary"
                  )}
                >
                  {opt === "auto"
                    ? "Auto"
                    : opt === "avplayer"
                    ? "AVPlayer"
                    : "VLCKit"}
                </button>
              ))}
            </div>
            <p className="mt-1.5 text-xs text-text-muted">
              Auto uses AVPlayer for HLS/MP4, VLCKit for other formats
            </p>
          </div>

          {/* Resume playback */}
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium">Resume Playback</p>
              <p className="text-xs text-text-muted">
                Automatically resume from where you left off
              </p>
            </div>
            <button
              onClick={() => setResume(!resume)}
              className={cn(
                "relative h-6 w-11 rounded-full transition-colors",
                resume ? "bg-accent" : "bg-surface-overlay"
              )}
            >
              <span
                className={cn(
                  "absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white transition-transform",
                  resume && "translate-x-5"
                )}
              />
            </button>
          </div>

          {/* Buffer timeout */}
          <div>
            <label className="mb-2 block text-sm font-medium">
              Buffer Timeout: {bufferTimeout}s
            </label>
            <input
              type="range"
              min={5}
              max={30}
              step={5}
              value={bufferTimeout}
              onChange={(e) => setBufferTimeout(Number(e.target.value))}
              className="w-full accent-accent"
            />
            <div className="mt-1 flex justify-between text-xs text-text-muted">
              <span>5s</span>
              <span>30s</span>
            </div>
          </div>
        </div>
      </section>

      {/* Save */}
      <button
        onClick={handleSave}
        disabled={!db}
        className={cn(
          "flex items-center gap-2 rounded-lg px-6 py-2.5 text-sm font-medium transition-colors",
          saved
            ? "bg-accent/20 text-accent"
            : "bg-accent text-surface hover:bg-accent-hover",
          !db && "opacity-50 cursor-not-allowed"
        )}
      >
        {saved ? (
          <>
            <Check className="h-4 w-4" />
            Saved
          </>
        ) : (
          <>
            <Save className="h-4 w-4" />
            Save Preferences
          </>
        )}
      </button>
    </div>
  );
}
