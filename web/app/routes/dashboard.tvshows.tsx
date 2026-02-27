import { useState, useMemo } from "react";
import { redirect } from "react-router";
import { MonitorPlay, Search as SearchIcon, ChevronRight } from "lucide-react";
import type { Route } from "./+types/dashboard.tvshows";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { useQuery } from "~/hooks/use-query";
import { EmptyState } from "~/components/empty-state";
import { HlsPlayer } from "~/components/hls-player";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");

  const { data: shows } = await supabase
    .from("vod_items")
    .select("*")
    .in("type", ["series", "episode"])
    .order("title");

  return { shows: shows ?? [] };
}

interface VodItem {
  id: string;
  title: string;
  type: string;
  stream_url: string;
  logo_url: string;
  genre: string;
  year: number;
  season_num: number;
  episode_num: number;
  series_id: string;
  plot: string;
  rating: string;
}

export default function TVShowsPage({ loaderData }: Route.ComponentProps) {
  const { data: liveShows } = useQuery<VodItem>(
    "SELECT * FROM vod_items WHERE type IN ('series', 'episode') ORDER BY title"
  );
  const allItems = liveShows.length > 0 ? liveShows : (loaderData.shows as VodItem[]);

  const [search, setSearch] = useState("");
  const [genreFilter, setGenreFilter] = useState<string | null>(null);
  const [selectedSeries, setSelectedSeries] = useState<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewTitle, setPreviewTitle] = useState("");

  // Separate series from episodes
  const series = useMemo(
    () => allItems.filter((i) => i.type === "series"),
    [allItems]
  );
  const episodes = useMemo(
    () => allItems.filter((i) => i.type === "episode"),
    [allItems]
  );

  const genres = useMemo(() => {
    const set = new Set(series.map((s) => s.genre).filter(Boolean));
    return Array.from(set).sort();
  }, [series]);

  const filteredSeries = useMemo(() => {
    let result = series;
    if (search) {
      const q = search.toLowerCase();
      result = result.filter((s) => s.title.toLowerCase().includes(q));
    }
    if (genreFilter) {
      result = result.filter((s) => s.genre === genreFilter);
    }
    return result;
  }, [series, search, genreFilter]);

  // Episodes for selected series
  const seriesEpisodes = useMemo(() => {
    if (!selectedSeries) return [];
    return episodes
      .filter((e) => e.series_id === selectedSeries)
      .sort((a, b) => (a.season_num || 0) - (b.season_num || 0) || (a.episode_num || 0) - (b.episode_num || 0));
  }, [episodes, selectedSeries]);

  // Group episodes by season
  const seasons = useMemo(() => {
    const map = new Map<number, VodItem[]>();
    seriesEpisodes.forEach((ep) => {
      const s = ep.season_num || 1;
      if (!map.has(s)) map.set(s, []);
      map.get(s)!.push(ep);
    });
    return Array.from(map.entries()).sort(([a], [b]) => a - b);
  }, [seriesEpisodes]);

  const selectedSeriesItem = series.find((s) => s.id === selectedSeries);

  if (selectedSeries) {
    return (
      <div className="flex gap-6">
        <div className="flex-1">
          <button
            onClick={() => setSelectedSeries(null)}
            className="mb-4 flex items-center gap-1 text-sm text-text-secondary hover:text-text-primary"
          >
            &larr; Back to TV Shows
          </button>

          <div className="mb-6 flex gap-4">
            {selectedSeriesItem?.logo_url && (
              <img
                src={selectedSeriesItem.logo_url}
                alt=""
                className="h-40 w-28 rounded-lg object-cover"
              />
            )}
            <div>
              <h1 className="text-2xl font-bold">{selectedSeriesItem?.title}</h1>
              <div className="mt-1 flex gap-3 text-sm text-text-secondary">
                {selectedSeriesItem?.year && <span>{selectedSeriesItem.year}</span>}
                {selectedSeriesItem?.rating && <span>{selectedSeriesItem.rating}</span>}
                {selectedSeriesItem?.genre && <span>{selectedSeriesItem.genre}</span>}
              </div>
              {selectedSeriesItem?.plot && (
                <p className="mt-3 max-w-xl text-sm leading-relaxed text-text-secondary">
                  {selectedSeriesItem.plot}
                </p>
              )}
            </div>
          </div>

          {seasons.map(([seasonNum, eps]) => (
            <div key={seasonNum} className="mb-6">
              <h2 className="mb-3 text-lg font-semibold">Season {seasonNum}</h2>
              <div className="space-y-1">
                {eps.map((ep) => (
                  <div
                    key={ep.id}
                    className="flex items-center gap-3 rounded-lg px-3 py-2 transition-colors hover:bg-surface-raised cursor-pointer"
                    onClick={() => {
                      if (ep.stream_url) {
                        setPreviewUrl(ep.stream_url);
                        setPreviewTitle(`S${ep.season_num}E${ep.episode_num} - ${ep.title}`);
                      }
                    }}
                  >
                    <span className="w-8 text-center text-sm text-text-muted">
                      {ep.episode_num}
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{ep.title}</p>
                    </div>
                    <ChevronRight className="h-4 w-4 text-text-muted" />
                  </div>
                ))}
              </div>
            </div>
          ))}

          {seasons.length === 0 && (
            <p className="py-8 text-center text-sm text-text-muted">
              No episodes found for this series.
            </p>
          )}
        </div>

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

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold">TV Shows</h1>
        <p className="mt-1 text-sm text-text-secondary">
          {series.length} series available
        </p>
      </div>

      <div className="mb-6 flex flex-wrap items-center gap-3">
        <div className="relative w-72">
          <SearchIcon className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search TV shows..."
            className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-text-primary placeholder:text-text-muted focus:border-accent focus:outline-none"
          />
        </div>
        <select
          value={genreFilter ?? ""}
          onChange={(e) => setGenreFilter(e.target.value || null)}
          className="rounded-lg border border-border bg-surface px-3 py-2 text-sm text-text-primary focus:border-accent focus:outline-none"
        >
          <option value="">All Genres</option>
          {genres.map((g) => (
            <option key={g} value={g}>{g}</option>
          ))}
        </select>
      </div>

      {filteredSeries.length === 0 ? (
        <EmptyState
          icon={MonitorPlay}
          title={series.length === 0 ? "No TV shows yet" : "No matches"}
          description={
            series.length === 0
              ? "TV shows will appear after importing from an Xtream or Emby source."
              : "Try adjusting your search or filters."
          }
        />
      ) : (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
          {filteredSeries.map((show) => (
            <div
              key={show.id}
              className="group cursor-pointer overflow-hidden rounded-xl border border-border bg-surface-raised transition-colors hover:border-border-hover"
              onClick={() => setSelectedSeries(show.id)}
            >
              <div className="relative aspect-[2/3] bg-surface">
                {show.logo_url ? (
                  <img
                    src={show.logo_url}
                    alt={show.title}
                    className="h-full w-full object-cover"
                    loading="lazy"
                  />
                ) : (
                  <div className="flex h-full items-center justify-center">
                    <MonitorPlay className="h-8 w-8 text-text-muted" />
                  </div>
                )}
                {show.rating && (
                  <span className="absolute right-2 top-2 rounded-md bg-black/70 px-1.5 py-0.5 text-xs font-medium text-accent">
                    {show.rating}
                  </span>
                )}
              </div>
              <div className="p-3">
                <p className="truncate text-sm font-medium">{show.title}</p>
                <div className="mt-1 flex items-center gap-2 text-xs text-text-secondary">
                  {show.year > 0 && <span>{show.year}</span>}
                  {show.genre && <span>{show.genre}</span>}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
