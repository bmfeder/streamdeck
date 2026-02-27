import { type RouteConfig, index, layout, route } from "@react-router/dev/routes";

export default [
  index("routes/_index.tsx"),
  route("login", "routes/login.tsx"),
  route("auth/callback", "routes/auth.callback.tsx"),
  route("dashboard", "routes/dashboard.tsx", [
    index("routes/dashboard._index.tsx"),
    route("playlists", "routes/dashboard.playlists.tsx"),
    route("playlists/:id", "routes/dashboard.playlists.$id.tsx"),
    route("channels", "routes/dashboard.channels.tsx"),
    route("movies", "routes/dashboard.movies.tsx"),
    route("tvshows", "routes/dashboard.tvshows.tsx"),
    route("progress", "routes/dashboard.progress.tsx"),
    route("settings", "routes/dashboard.settings.tsx"),
  ]),
] satisfies RouteConfig;
