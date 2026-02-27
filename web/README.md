# StreamDeck Web Dashboard

Web-based management dashboard for StreamDeck IPTV playlists. Built with React Router 7 (Framework Mode), Tailwind CSS v4, and PowerSync for real-time bidirectional sync with the tvOS/iOS app.

## Stack

- **Framework**: React Router 7 (SSR + client)
- **Styling**: Tailwind CSS v4, dark theme (#00ff9d accent)
- **Auth**: Apple Sign In via Supabase OAuth
- **Sync**: PowerSync (local-first SQLite via WASM, syncs to Supabase)
- **Player**: hls.js for HLS stream preview
- **Icons**: lucide-react

## Setup

```bash
cp .env.example .env    # Add your Supabase + PowerSync credentials
npm install
npm run dev             # http://localhost:5173
```

Required environment variables (see `.env.example`):
- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_ANON_KEY` — Supabase anon/public key
- `POWERSYNC_URL` — PowerSync Cloud instance URL

## Architecture

- **Server loaders** fetch initial data from Supabase (fast SSR)
- **PowerSync** initializes client-side via dynamic imports (avoids WASM in SSR)
- **`useQuery` hook** watches PowerSync for reactive updates after hydration
- COOP/COEP headers configured for SharedArrayBuffer (PowerSync WASM)

## Routes

| Path | Description |
|------|-------------|
| `/login` | Apple Sign In |
| `/auth/callback` | OAuth code exchange |
| `/dashboard/playlists` | Source management (add/delete M3U/Xtream/Emby) |
| `/dashboard/playlists/:id` | Playlist detail — channels, search, favorites, HLS preview |
| `/dashboard/channels` | Live TV grid — group filter, search, favorites |
| `/dashboard/movies` | Movie catalog — genre filter, detail panel |
| `/dashboard/tvshows` | TV shows — series drill-down, season/episode |
| `/dashboard/progress` | Watch history — progress bars, clear |
| `/dashboard/settings` | Preferences — player engine, resume, buffer timeout |

## File Structure

```
app/
├── components/          7 components (sidebar, topbar, hls-player, etc.)
├── hooks/               useQuery (PowerSync), useAuth (Supabase)
├── lib/                 PowerSync provider, Supabase clients, schema, utils
├── routes/              12 route files
├── root.tsx             Root layout with env loader
├── routes.ts            Route configuration
└── app.css              Dark theme with Tailwind v4 @theme
```

## Build

```bash
npm run build           # Production build (client + server)
npm run start           # Serve production build
npm run typecheck       # TypeScript check
```
