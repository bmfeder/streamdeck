import { useState, useMemo } from "react";
import { redirect } from "react-router";
import { Film, Search as SearchIcon } from "lucide-react";
import type { Route } from "./+types/dashboard.movies";
import { createSupabaseServerClient } from "~/lib/supabase.server";
import { useQuery } from "~/hooks/use-query";
import { EmptyState } from "~/components/empty-state";
import { HlsPlayer } from "~/components/hls-player";
import { cn, formatDuration } from "~/lib/utils";

export async function loader({ request }: Route.LoaderArgs) {
  const { supabase } = createSupabaseServerClient(request);
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw redirect("/login");

  const { data: movies } = await supabase
    .from("vod_items")
    .select("*")
    .eq("type", "movie")
    .order("title");

  return { movies: movies ?? [] };
}

interface Movie {
  id: string;
  title: string;
  stream_url: string;
  logo_url: string;
  genre: string;
  year: number;
  rating: string;
  duration: number;
  plot: string;
}

export default function MoviesPage({ loaderData }: Route.ComponentProps) {
  const { data: liveMovies } = useQuery<Movie>(
    "SELECT * FROM vod_items WHERE type = 'movie' ORDER BY title"
  );
  const movies = liveMovies.length > 0 ? liveMovies : (loaderData.movies as Movie[]);

  const [search, setSearch] = useState("");
  const [genreFilter, setGenreFilter] = useState<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewTitle, setPreviewTitle] = useState("");
  const [selectedMovie, setSelectedMovie] = useState<Movie | null>(null);

  const genres = useMemo(() => {
    const set = new Set(movies.map((m) => m.genre).filter(Boolean));
    return Array.from(set).sort();
  }, [movies]);

  const filtered = useMemo(() => {
    let result = movies;
    if (search) {
      const q = search.toLowerCase();
      result = result.filter((m) => m.title.toLowerCase().includes(q));
    }
    if (genreFilter) {
      result = result.filter((m) => m.genre === genreFilter);
    }
    return result;
  }, [movies, search, genreFilter]);

  return (
    <div className="flex gap-6">
      <div className="flex-1">
        <div className="mb-6">
          <h1 className="text-2xl font-bold">Movies</h1>
          <p className="mt-1 text-sm text-text-secondary">
            {movies.length} movies available
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
              placeholder="Search movies..."
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

        {/* Grid */}
        {filtered.length === 0 ? (
          <EmptyState
            icon={Film}
            title={movies.length === 0 ? "No movies yet" : "No matches"}
            description={
              movies.length === 0
                ? "Movies will appear after importing from an Xtream or Emby source."
                : "Try adjusting your search or filters."
            }
          />
        ) : (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
            {filtered.map((movie) => (
              <div
                key={movie.id}
                className="group cursor-pointer overflow-hidden rounded-xl border border-border bg-surface-raised transition-colors hover:border-border-hover"
                onClick={() => {
                  setSelectedMovie(movie);
                  if (movie.stream_url) {
                    setPreviewUrl(movie.stream_url);
                    setPreviewTitle(movie.title);
                  }
                }}
              >
                {/* Poster */}
                <div className="relative aspect-[2/3] bg-surface">
                  {movie.logo_url ? (
                    <img
                      src={movie.logo_url}
                      alt={movie.title}
                      className="h-full w-full object-cover"
                      loading="lazy"
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center">
                      <Film className="h-8 w-8 text-text-muted" />
                    </div>
                  )}
                  {movie.rating && (
                    <span className="absolute right-2 top-2 rounded-md bg-black/70 px-1.5 py-0.5 text-xs font-medium text-accent">
                      {movie.rating}
                    </span>
                  )}
                </div>
                {/* Info */}
                <div className="p-3">
                  <p className="truncate text-sm font-medium">{movie.title}</p>
                  <div className="mt-1 flex items-center gap-2 text-xs text-text-secondary">
                    {movie.year > 0 && <span>{movie.year}</span>}
                    {movie.duration > 0 && <span>{formatDuration(movie.duration)}</span>}
                  </div>
                  {movie.genre && (
                    <p className="mt-1 truncate text-xs text-text-muted">{movie.genre}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Preview/Detail panel */}
      {previewUrl && (
        <div className="w-96 shrink-0">
          <div className="sticky top-20 space-y-4">
            <HlsPlayer
              url={previewUrl}
              title={previewTitle}
              onClose={() => {
                setPreviewUrl(null);
                setSelectedMovie(null);
              }}
            />
            {selectedMovie?.plot && (
              <div className="rounded-xl border border-border bg-surface-raised p-4">
                <h3 className="mb-2 font-medium">{selectedMovie.title}</h3>
                <p className="text-sm leading-relaxed text-text-secondary">
                  {selectedMovie.plot}
                </p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
