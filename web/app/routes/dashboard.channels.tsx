import { useState, useMemo } from "react";
import { redirect, useSearchParams } from "react-router";
import { Tv, Search as SearchIcon } from "lucide-react";
import type { Route } from "./+types/dashboard.channels";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { useQuery } from "~/hooks/use-query";
import { usePowerSync } from "~/lib/powersync-provider";
import { ChannelCard } from "~/components/channel-card";
import { HlsPlayer } from "~/components/hls-player";
import { EmptyState } from "~/components/empty-state";
import { cn } from "~/lib/utils";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");

  const { data: channels } = await supabase
    .from("channels")
    .select("*")
    .eq("is_deleted", false)
    .order("name");

  return { channels: channels ?? [] };
}

interface Channel {
  id: string;
  playlist_id: string;
  name: string;
  group_name: string;
  logo_url: string;
  stream_url: string;
  channel_number: number;
  is_favorite: number;
}

export default function ChannelsPage({ loaderData }: Route.ComponentProps) {
  const db = usePowerSync();
  const [searchParams] = useSearchParams();
  const initialQuery = searchParams.get("q") ?? "";

  const { data: liveChannels } = useQuery<Channel>(
    "SELECT * FROM channels WHERE is_deleted = 0 ORDER BY name"
  );
  const channels = liveChannels.length > 0 ? liveChannels : (loaderData.channels as Channel[]);

  const [search, setSearch] = useState(initialQuery);
  const [groupFilter, setGroupFilter] = useState<string | null>(null);
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewTitle, setPreviewTitle] = useState("");

  const groups = useMemo(() => {
    const set = new Set(channels.map((c) => c.group_name).filter(Boolean));
    return Array.from(set).sort();
  }, [channels]);

  const filtered = useMemo(() => {
    let result = channels;
    if (search) {
      const q = search.toLowerCase();
      result = result.filter((c) => c.name.toLowerCase().includes(q));
    }
    if (groupFilter) {
      result = result.filter((c) => c.group_name === groupFilter);
    }
    if (favoritesOnly) {
      result = result.filter((c) => c.is_favorite);
    }
    return result;
  }, [channels, search, groupFilter, favoritesOnly]);

  const toggleFavorite = async (channelId: string, current: number) => {
    if (!db) return;
    await db.execute(
      "UPDATE channels SET is_favorite = ?, updated_at = ? WHERE id = ?",
      [current ? 0 : 1, new Date().toISOString(), channelId]
    );
  };

  return (
    <div className="flex gap-6">
      <div className="flex-1">
        <div className="mb-6">
          <h1 className="text-2xl font-bold">Live TV</h1>
          <p className="mt-1 text-sm text-text-secondary">
            {channels.length} channels across all sources
          </p>
        </div>

        {/* Filters */}
        <div className="mb-6 flex flex-wrap items-center gap-3">
          <div className="relative w-72">
            <SearchIcon className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
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
              <option key={g} value={g}>{g}</option>
            ))}
          </select>
          <button
            onClick={() => setFavoritesOnly(!favoritesOnly)}
            className={cn(
              "rounded-lg px-3 py-2 text-sm font-medium transition-colors",
              favoritesOnly
                ? "bg-accent/10 text-accent"
                : "bg-surface-overlay text-text-secondary hover:text-text-primary"
            )}
          >
            Favorites
          </button>
        </div>

        {/* Grid */}
        {filtered.length === 0 ? (
          <EmptyState
            icon={Tv}
            title={channels.length === 0 ? "No channels yet" : "No matches"}
            description={
              channels.length === 0
                ? "Add a source to import channels."
                : "Try adjusting your search or filters."
            }
          />
        ) : (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
            {filtered.map((ch) => (
              <ChannelCard
                key={ch.id}
                id={ch.id}
                name={ch.name}
                groupName={ch.group_name}
                logoUrl={ch.logo_url}
                channelNumber={ch.channel_number}
                isFavorite={!!ch.is_favorite}
                onToggleFavorite={() => toggleFavorite(ch.id, ch.is_favorite)}
                onPlay={() => {
                  setPreviewUrl(ch.stream_url);
                  setPreviewTitle(ch.name);
                }}
              />
            ))}
          </div>
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
