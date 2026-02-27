import { useState, useMemo } from "react";
import { useParams, Link, redirect } from "react-router";
import {
  ArrowLeft,
  GripVertical,
  Star,
  Play,
  Search,
  Filter,
} from "lucide-react";
import type { Route } from "./+types/dashboard.playlists.$id";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { useQuery } from "~/hooks/use-query";
import { usePowerSync } from "~/lib/powersync-provider";
import { HlsPlayer } from "~/components/hls-player";
import { cn } from "~/lib/utils";

export async function loader({ request, params }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");

  const [{ data: playlist }, { data: channels }] = await Promise.all([
    supabase.from("playlists").select("*").eq("id", params.id).single(),
    supabase
      .from("channels")
      .select("*")
      .eq("playlist_id", params.id)
      .eq("is_deleted", false)
      .order("channel_number"),
  ]);

  return { playlist, channels: channels ?? [] };
}

interface Channel {
  id: string;
  name: string;
  group_name: string;
  logo_url: string;
  stream_url: string;
  channel_number: number;
  is_favorite: number;
}

export default function PlaylistDetailPage({ loaderData }: Route.ComponentProps) {
  const { id } = useParams();
  const db = usePowerSync();

  const { data: liveChannels } = useQuery<Channel>(
    "SELECT * FROM channels WHERE playlist_id = ? AND is_deleted = 0 ORDER BY channel_number",
    [id!]
  );
  const channels = liveChannels.length > 0 ? liveChannels : (loaderData.channels as Channel[]);

  const [search, setSearch] = useState("");
  const [groupFilter, setGroupFilter] = useState<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewTitle, setPreviewTitle] = useState("");

  // Get unique groups
  const groups = useMemo(() => {
    const set = new Set(channels.map((c) => c.group_name).filter(Boolean));
    return Array.from(set).sort();
  }, [channels]);

  // Filtered channels
  const filtered = useMemo(() => {
    let result = channels;
    if (search) {
      const q = search.toLowerCase();
      result = result.filter((c) => c.name.toLowerCase().includes(q));
    }
    if (groupFilter) {
      result = result.filter((c) => c.group_name === groupFilter);
    }
    return result;
  }, [channels, search, groupFilter]);

  const toggleFavorite = async (channelId: string, current: number) => {
    if (!db) return;
    await db.execute(
      "UPDATE channels SET is_favorite = ?, updated_at = ? WHERE id = ?",
      [current ? 0 : 1, new Date().toISOString(), channelId]
    );
  };

  return (
    <div className="flex gap-6">
      {/* Channel list */}
      <div className="flex-1">
        <div className="mb-4 flex items-center gap-3">
          <Link
            to="/dashboard/playlists"
            className="rounded-lg p-2 text-text-secondary hover:bg-surface-hover hover:text-text-primary"
          >
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <div>
            <h1 className="text-xl font-bold">
              {loaderData.playlist?.name ?? "Playlist"}
            </h1>
            <p className="text-sm text-text-secondary">
              {channels.length} channels
            </p>
          </div>
        </div>

        {/* Filters */}
        <div className="mb-4 flex gap-3">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search channels..."
              className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-text-primary placeholder:text-text-muted focus:border-accent focus:outline-none"
            />
          </div>
          <select
            value={groupFilter ?? ""}
            onChange={(e) => setGroupFilter(e.target.value || null)}
            className="rounded-lg border border-border bg-surface px-3 py-2 text-sm text-text-primary focus:border-accent focus:outline-none"
          >
            <option value="">All Groups</option>
            {groups.map((g) => (
              <option key={g} value={g}>
                {g}
              </option>
            ))}
          </select>
        </div>

        {/* Channel rows */}
        <div className="space-y-1">
          {filtered.map((ch) => (
            <div
              key={ch.id}
              className="flex items-center gap-3 rounded-lg border border-transparent px-3 py-2 transition-colors hover:border-border hover:bg-surface-raised"
            >
              <GripVertical className="h-4 w-4 shrink-0 cursor-grab text-text-muted" />

              {/* Logo */}
              <div className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-md bg-surface-overlay">
                {ch.logo_url ? (
                  <img
                    src={ch.logo_url}
                    alt=""
                    className="h-full w-full object-contain p-1"
                    loading="lazy"
                  />
                ) : (
                  <span className="text-xs font-bold text-text-muted">
                    {ch.channel_number || ch.name.charAt(0)}
                  </span>
                )}
              </div>

              {/* Info */}
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{ch.name}</p>
                {ch.group_name && (
                  <p className="truncate text-xs text-text-secondary">
                    {ch.group_name}
                  </p>
                )}
              </div>

              {/* Actions */}
              <button
                onClick={() => toggleFavorite(ch.id, ch.is_favorite)}
                className={cn(
                  "rounded-md p-1.5 transition-colors",
                  ch.is_favorite
                    ? "text-accent"
                    : "text-text-muted hover:text-text-secondary"
                )}
              >
                <Star
                  className="h-4 w-4"
                  fill={ch.is_favorite ? "currentColor" : "none"}
                />
              </button>
              <button
                onClick={() => {
                  setPreviewUrl(ch.stream_url);
                  setPreviewTitle(ch.name);
                }}
                className="rounded-md p-1.5 text-text-muted hover:text-accent transition-colors"
              >
                <Play className="h-4 w-4" />
              </button>
            </div>
          ))}
        </div>

        {filtered.length === 0 && (
          <p className="py-12 text-center text-sm text-text-muted">
            No channels found
          </p>
        )}
      </div>

      {/* Preview panel */}
      {previewUrl && (
        <div className="w-96 shrink-0">
          <div className="sticky top-20">
            <HlsPlayer
              url={previewUrl}
              title={previewTitle}
              onClose={() => setPreviewUrl(null)}
            />
          </div>
        </div>
      )}
    </div>
  );
}
