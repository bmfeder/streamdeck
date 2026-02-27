import { useState } from "react";
import { redirect } from "react-router";
import { HardDrive, Plus, RefreshCw, Trash2, Edit, Tv, Film } from "lucide-react";
import type { Route } from "./+types/dashboard.playlists";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { useQuery } from "~/hooks/use-query";
import { usePowerSync } from "~/lib/powersync-provider";
import { EmptyState } from "~/components/empty-state";
import { AddPlaylistDialog, type PlaylistFormData } from "~/components/add-playlist-dialog";
import { cn } from "~/lib/utils";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");

  const { data: playlists } = await supabase
    .from("playlists")
    .select("*")
    .order("sort_order");

  return { playlists: playlists ?? [] };
}

interface Playlist {
  id: string;
  name: string;
  type: string;
  url: string;
  username: string;
  epg_url: string;
  refresh_hrs: number;
  is_active: number;
  sort_order: number;
  last_sync: string;
  created_at: string;
  updated_at: string;
}

export default function PlaylistsPage({ loaderData }: Route.ComponentProps) {
  const db = usePowerSync();
  const { data: livePlaylists } = useQuery<Playlist>(
    "SELECT * FROM playlists ORDER BY sort_order"
  );
  const playlists = livePlaylists.length > 0 ? livePlaylists : (loaderData.playlists as Playlist[]);

  const [showAdd, setShowAdd] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);

  const handleAdd = async (data: PlaylistFormData) => {
    if (!db) return;
    const id = crypto.randomUUID();
    const now = new Date().toISOString();

    await db.execute(
      `INSERT INTO playlists (id, name, type, url, username, epg_url, refresh_hrs, is_active, sort_order, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)`,
      [id, data.name, data.type, data.url, data.username ?? "", data.epgUrl ?? "", data.refreshHrs, playlists.length, now, now]
    );
    setShowAdd(false);
  };

  const handleDelete = async (id: string) => {
    if (!db || !confirm("Delete this source and all its channels?")) return;
    await db.execute("DELETE FROM channels WHERE playlist_id = ?", [id]);
    await db.execute("DELETE FROM playlists WHERE id = ?", [id]);
  };

  const handleToggleActive = async (id: string, currentActive: number) => {
    if (!db) return;
    await db.execute(
      "UPDATE playlists SET is_active = ?, updated_at = ? WHERE id = ?",
      [currentActive ? 0 : 1, new Date().toISOString(), id]
    );
  };

  const typeIcon = (type: string) => {
    switch (type) {
      case "xtream": return <Tv className="h-4 w-4" />;
      case "emby": return <Film className="h-4 w-4" />;
      default: return <HardDrive className="h-4 w-4" />;
    }
  };

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Sources</h1>
          <p className="mt-1 text-sm text-text-secondary">
            Manage your M3U, Xtream, and Emby sources
          </p>
        </div>
        <button
          onClick={() => setShowAdd(true)}
          className="flex items-center gap-2 rounded-lg bg-accent px-4 py-2 text-sm font-medium text-surface hover:bg-accent-hover transition-colors"
        >
          <Plus className="h-4 w-4" />
          Add Source
        </button>
      </div>

      {playlists.length === 0 ? (
        <EmptyState
          icon={HardDrive}
          title="No sources yet"
          description="Add your first M3U, Xtream, or Emby source to start browsing channels and movies."
          action={{ label: "Add Source", onClick: () => setShowAdd(true) }}
        />
      ) : (
        <div className="space-y-3">
          {playlists.map((pl) => (
            <div
              key={pl.id}
              className={cn(
                "flex items-center gap-4 rounded-xl border border-border bg-surface-raised p-4 transition-colors hover:border-border-hover",
                !pl.is_active && "opacity-50"
              )}
            >
              {/* Type icon */}
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-surface-overlay text-accent">
                {typeIcon(pl.type)}
              </div>

              {/* Info */}
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <h3 className="truncate font-medium">{pl.name}</h3>
                  <span className="shrink-0 rounded-md bg-surface-overlay px-2 py-0.5 text-xs text-text-secondary uppercase">
                    {pl.type}
                  </span>
                </div>
                <p className="mt-0.5 truncate text-sm text-text-secondary">
                  {pl.url}
                </p>
                <div className="mt-1 flex gap-4 text-xs text-text-muted">
                  <span>Refresh: {pl.refresh_hrs}h</span>
                  {pl.last_sync && (
                    <span>
                      Last sync: {new Date(pl.last_sync).toLocaleDateString()}
                    </span>
                  )}
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center gap-1">
                <button
                  onClick={() => handleToggleActive(pl.id, pl.is_active)}
                  className={cn(
                    "rounded-lg px-3 py-1.5 text-xs font-medium transition-colors",
                    pl.is_active
                      ? "bg-accent/10 text-accent"
                      : "bg-surface-overlay text-text-muted"
                  )}
                >
                  {pl.is_active ? "Active" : "Disabled"}
                </button>
                <button
                  onClick={() => handleDelete(pl.id)}
                  className="rounded-md p-2 text-text-muted hover:bg-surface-hover hover:text-danger transition-colors"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <AddPlaylistDialog
        open={showAdd}
        onClose={() => setShowAdd(false)}
        onSubmit={handleAdd}
      />
    </div>
  );
}
