import { redirect } from "react-router";
import { Clock, Trash2, RotateCcw } from "lucide-react";
import type { Route } from "./+types/dashboard.progress";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { useQuery } from "~/hooks/use-query";
import { usePowerSync } from "~/lib/powersync-provider";
import { EmptyState } from "~/components/empty-state";
import { formatDuration, formatProgress } from "~/lib/utils";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");

  const { data: progress } = await supabase
    .from("watch_progress")
    .select("*")
    .order("updated_at", { ascending: false });

  return { progress: progress ?? [] };
}

interface WatchProgress {
  id: string;
  content_id: string;
  playlist_id: string;
  position_ms: number;
  duration_ms: number;
  updated_at: string;
}

export default function ProgressPage({ loaderData }: Route.ComponentProps) {
  const db = usePowerSync();

  const { data: liveProgress } = useQuery<WatchProgress>(
    "SELECT * FROM watch_progress ORDER BY updated_at DESC"
  );
  const progress = liveProgress.length > 0 ? liveProgress : (loaderData.progress as WatchProgress[]);

  const handleDelete = async (id: string) => {
    if (!db) return;
    await db.execute("DELETE FROM watch_progress WHERE id = ?", [id]);
  };

  const handleClearAll = async () => {
    if (!db || !confirm("Clear all watch history?")) return;
    await db.execute("DELETE FROM watch_progress");
  };

  const progressPercent = (p: WatchProgress) => {
    if (!p.duration_ms || p.duration_ms <= 0) return 0;
    return Math.min(Math.round((p.position_ms / p.duration_ms) * 100), 100);
  };

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Watch History</h1>
          <p className="mt-1 text-sm text-text-secondary">
            {progress.length} items
          </p>
        </div>
        {progress.length > 0 && (
          <button
            onClick={handleClearAll}
            className="flex items-center gap-2 rounded-lg px-4 py-2 text-sm text-danger hover:bg-surface-raised transition-colors"
          >
            <Trash2 className="h-4 w-4" />
            Clear All
          </button>
        )}
      </div>

      {progress.length === 0 ? (
        <EmptyState
          icon={Clock}
          title="No watch history"
          description="Your watch progress will be tracked here as you watch channels and movies."
        />
      ) : (
        <div className="space-y-2">
          {progress.map((p) => (
            <div
              key={p.id}
              className="flex items-center gap-4 rounded-xl border border-border bg-surface-raised p-4 transition-colors hover:border-border-hover"
            >
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-surface-overlay text-accent">
                <RotateCcw className="h-4 w-4" />
              </div>

              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{p.content_id}</p>
                <div className="mt-1 flex items-center gap-3 text-xs text-text-secondary">
                  <span>
                    {Math.floor(p.position_ms / 60000)}m /{" "}
                    {p.duration_ms ? `${Math.floor(p.duration_ms / 60000)}m` : "?"}
                  </span>
                  <span>{new Date(p.updated_at).toLocaleDateString()}</span>
                </div>

                {/* Progress bar */}
                <div className="mt-2 h-1.5 w-full rounded-full bg-surface-overlay">
                  <div
                    className="h-full rounded-full bg-accent"
                    style={{ width: `${progressPercent(p)}%` }}
                  />
                </div>
              </div>

              <span className="shrink-0 text-sm text-text-muted">
                {formatProgress(p.position_ms, p.duration_ms)}
              </span>

              <button
                onClick={() => handleDelete(p.id)}
                className="shrink-0 rounded-md p-2 text-text-muted hover:bg-surface-hover hover:text-danger transition-colors"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
