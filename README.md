# StreamDeck

A blazing-fast, native media player for IPTV and Emby with a web dashboard for remote management.

**Status:** Phase 4 in progress — 734 Swift tests, web dashboard built

## Overview

Cross-platform media player built with native performance as the north star. tvOS-first design with M3U/Xtream Codes IPTV support, full Emby integration, and a web dashboard for playlist management and browsing.

## Tech Stack

| Layer | Apple (tvOS/iOS) | Web Dashboard | Shared |
|-------|-------------------|---------------|--------|
| UI | SwiftUI + TCA | React Router 7 + shadcn/ui | — |
| Video | AVPlayer + VLCKit | hls.js | — |
| Parsing | — | — | M3U / Xtream / XMLTV |
| Local Storage | GRDB.swift (EPG) | PowerSync SQLite | — |
| Sync | PowerSync Swift SDK | PowerSync JS SDK | Supabase (PostgreSQL) |
| Auth | Apple Sign In (native) | Apple Sign In (OAuth) | Supabase Auth |

## Project Structure

```
streamdeck/
├── App/                 tvOS + iOS app target (SwiftUI @main)
├── StreamDeck/          Swift Package (8 modules, 734 tests)
│   ├── Sources/
│   │   ├── M3UParser/       M3U playlist parser
│   │   ├── XtreamClient/    Xtream Codes API client
│   │   ├── XMLTVParser/     XMLTV EPG parser (SAX-style)
│   │   ├── EmbyClient/      Emby server API client
│   │   ├── Database/        GRDB schema + record types
│   │   ├── Repositories/    Data repos, import services, sync
│   │   └── AppFeature/      TCA features, views, dependencies
│   └── Tests/
├── web-dashboard/       Supabase schema + PowerSync config
│   ├── supabase/            SQL schema, RLS, indexes, triggers
│   └── powersync/           Sync rules configuration
├── web/                 React Router 7 web dashboard
│   ├── app/components/      Sidebar, topbar, HLS player, dialogs
│   ├── app/hooks/           PowerSync queries, auth state
│   ├── app/lib/             PowerSync provider, Supabase clients
│   └── app/routes/          12 routes (auth, dashboard, screens)
├── docs/                Design specification
└── tasks/               Task tracker
```

## Getting Started

### Swift (tvOS/iOS app)
```bash
cd StreamDeck
swift test          # Run all 734 tests
swift build         # Build all modules
```

### Xcode
```bash
# tvOS
xcodebuild -scheme StreamDeck -destination 'generic/platform=tvOS' build CODE_SIGNING_ALLOWED=NO -skipMacroValidation

# iOS
xcodebuild -scheme StreamDeck-iOS -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO -skipMacroValidation
```

### Web Dashboard
```bash
cd web
cp .env.example .env    # Configure Supabase + PowerSync URLs
npm install
npm run dev             # http://localhost:5173
npm run build           # Production build
```

## Completed Features

### Phase 0: Foundation
- M3U parser (41 tests), Xtream client (57 tests), XMLTV parser (57 tests)
- GRDB database schema with 5 record types, soft-delete, 15 indexes
- TCA skeleton with 8-tab sidebar and legal disclaimer gate
- GitHub Actions CI (3 jobs: Swift tests, tvOS build, iOS build)

### Phase 1: Core Playback
- Playlist import (M3U + Xtream Codes) with three-tier identity matching
- Channel grid UI with category filtering and favorites
- Video player with AVPlayer primary + retry/fallback engine logic
- EPG basics (now-playing on tiles) + full EPG grid view

### Phase 2: Content & Emby
- VOD extraction (Movies + TV Shows tabs with genre filtering)
- Watch progress tracking (resume playback, progress bars on tiles)
- Emby integration (auth, library browsing, series drill-down)

### Phase 3: Polish & Platform
- VLCKit fallback engine, channel switcher, sleep timer, channel number entry
- Now-playing mini-bar, empty/degraded states, user preferences
- Playlist editing, home recently-watched section, universal search
- CloudKit sync (LWW conflict resolution, fire-and-forget pushes)
- iOS companion app (shared codebase, platform-adaptive UI)
- Transport controls + scrubber, tvOS HIG refinement pass (15 files)
- Bug fixes: timer leaks, N+1 EPG query, SQL LIKE injection, soft-delete purge

### Phase 4: Web Dashboard (in progress)
- Supabase SQL schema (5 tables, 20 RLS policies, 15 indexes)
- PowerSync sync rules for bidirectional sync
- React Router 7 dashboard with 12 routes, 7 components:
  - Apple Sign In via Supabase OAuth
  - Sources: Add/delete M3U/Xtream/Emby playlists
  - Live TV: Channel grid with group filter, search, favorites
  - Movies: Poster grid with genre filter, detail panel
  - TV Shows: Series grid with season/episode drill-down
  - History: Watch progress with progress bars, clear all
  - Settings: Player engine, resume toggle, buffer timeout
  - HLS live preview player (hls.js)
  - PowerSync reactive queries (client-side, SSR-safe)
  - Dark theme with #00ff9d accent
- Next: Swift app PowerSync integration (replace CloudKit)

## Documentation

Open `docs/app-design-v2.html` in a browser for the full design specification including architecture, data model, roadmap, and NFR targets.

See `web-dashboard/supabase/SETUP.md` for Supabase + PowerSync setup instructions.

See `web/.env.example` for required environment variables to run the web dashboard.
