# CLAUDE.md — StreamDeck Project Context

## What is this project?
StreamDeck is a cross-platform IPTV/Emby media player app, similar to KDTivi. Priority platform is tvOS (Apple TV), with iOS companion, web dashboard, and future Android TV support.

## Architecture Decisions (locked in)

### Tech Stack
- **tvOS/iOS UI**: SwiftUI + UIKit (for AVPlayer wrapping). TCA (The Composable Architecture) for state management.
- **Web Dashboard**: React Router 7 (Framework Mode) + shadcn/ui + Tailwind CSS v4. Deployed on Cloudflare Workers.
- **Android TV UI** (future): Jetpack Compose for TV (androidx.tv:tv-material). Orbit MVI.
- **Shared Logic (KMP)**: Set up from day 1 but building Swift-first for now. Will migrate parsers/models to Kotlin when Android work begins.
- **Video**: AVPlayer (primary) + VLCKit (fallback). hls.js for web preview.
- **Networking**: URLSession (Swift), fetch (web).
- **Local Storage**: GRDB.swift (tvOS/iOS, local-only data like EPG). PowerSync SQLite (synced data).
- **Backend**: Supabase (PostgreSQL + Auth + RLS) — free tier.
- **Sync**: PowerSync Cloud — bidirectional, local-first, offline-first sync between Supabase, web dashboard, and tvOS/iOS app. Replaces CloudKit.
- **Auth**: Apple Sign In (native on tvOS/iOS via ASAuthorizationAppleIDProvider, OAuth on web via Supabase).
- **Security**: Keychain for local credentials. Supabase pgcrypto for cloud-synced passwords. Never store passwords in plaintext.
- **Subscriptions**: StoreKit 2 (Apple-only). Add RevenueCat when Android launches.

### Architecture Pattern
Four-layer clean architecture:
1. **Presentation** — SwiftUI views, TCA reducers, tvOS focus handlers; React Router 7 routes + shadcn/ui (web)
2. **Use Cases / Repos** — PlaylistRepository, ChannelRepository, EmbyRepository, etc.
3. **Domain (Shared)** — Parsers, models, Emby API client, search
4. **Data** — GRDB (local EPG), PowerSync SQLite (synced tables), Supabase PostgreSQL (backend), HTTP client, image cache

### Video Playback Pipeline
User selects → Resolve URL → FFprobeKit probe (<200ms) → Route to AVPlayer (HLS/MP4) or VLCKit (TS/MKV/RTSP/RTMP) → Playback. Reconnect with exponential backoff (3 retries, then fallback engine once). See capability matrix in docs/app-design-v2.html §02.

### Data Model Identity Strategy
Channels use three-tier IDs: `playlist_id` (source) → `source_channel_id` (provider-native) → `id` (app canonical). On playlist refresh, match by source_channel_id first, then tvg_id, then name+group. Update stream URLs but keep canonical ID stable. Soft-delete channels missing from refresh (purge after 30 days). This preserves favorites and watch progress across URL rotations.

## Project Structure
```
streamdeck/
├── CLAUDE.md                  ← you are here
├── StreamDeck.xcodeproj       ← Xcode project (tvOS + iOS targets)
├── .github/workflows/ci.yml   ← GitHub Actions CI (Swift tests + tvOS build + iOS build)
├── App/                       ← Shared app target (SwiftUI @main, tvOS + iOS)
│   └── StreamDeckApp.swift
├── StreamDeck/                ← Swift Package (all app modules + tests)
│   ├── Package.swift
│   ├── Sources/M3UParser/     ← M3U/M3U8 parser (41 tests)
│   ├── Sources/XtreamClient/  ← Xtream Codes API client (57 tests)
│   ├── Sources/XMLTVParser/   ← XMLTV EPG parser, SAX-style (57 tests)
│   ├── Sources/EmbyClient/    ← Emby server API client (26 tests)
│   ├── Sources/Database/      ← GRDB schema v2 (45 tests)
│   ├── Sources/Repositories/  ← Data repos, import services, CloudKit sync (190+ tests)
│   ├── Sources/AppFeature/    ← TCA features: 8 tabs, video player, search, settings (300+ tests)
│   └── Tests/
├── web-dashboard/             ← Supabase schema + PowerSync config
│   ├── supabase/              ← SQL schema, RLS policies, indexes, triggers
│   └── powersync/             ← Sync rules YAML
├── web/                       ← React Router 7 web dashboard
│   ├── app/
│   │   ├── components/        ← Sidebar, topbar, HLS player, dialogs (7 components)
│   │   ├── hooks/             ← useQuery (PowerSync), useAuth (Supabase)
│   │   ├── lib/               ← PowerSync provider, Supabase clients, schema, utils
│   │   └── routes/            ← 12 routes (auth, dashboard layout, 8 screens)
│   ├── vite.config.ts
│   └── package.json
├── Shared/                    ← KMP shared module (empty shell, for Android phase)
├── docs/
│   └── app-design-v2.html    ← full design spec (open in browser to read)
└── tasks/
    └── streamdeck-tasks.xlsx  ← Phase 0 + Phase 1 task tracker
```

## Current Status
- **Phase 0 — Complete**: Design spec, parsers, database schema, TCA skeleton, CI
- **Phase 1 — Complete**: Repositories, playlist import (M3U + Xtream), channel grid UI, video player (AVPlayer + retry/fallback), EPG basics + grid view
- **Phase 2 — Complete**: VOD extraction (Movies + TV Shows), watch progress tracking, disclaimer persistence, Emby integration
- **Phase 3 — Complete**: VLCKit fallback, channel switcher, sleep timer, channel number entry, now-playing mini-bar, empty/degraded states, user preferences, playlist editing, home recently-watched, CloudKit sync, universal search, iOS companion app, transport controls + scrubber, tvOS HIG refinement pass
- **Phase 4 (Web Dashboard) — In Progress**: Supabase schema + PowerSync sync rules (4.1 done), React Router 7 web dashboard (4.2 done). Next: Swift app PowerSync integration (4.3).
- Total: **734 tests** across 8 targets, all passing
- Web dashboard: 43 files, 12 routes, 7 components, clean typecheck + production build
- GitHub Actions CI: 3 jobs (Swift tests + tvOS build + iOS build) on macos-26

## What to Build Next (Phase 4: Web Dashboard)
1. ~~Supabase SQL schema, RLS, PowerSync sync rules~~ — DONE (web-dashboard/supabase/)
2. ~~React Router 7 web dashboard~~ — DONE (web/)
3. Swift app: replace CloudKit with PowerSync + Supabase auth
4. Polish: sync status, error handling, data export

## Coding Conventions

### Swift
- Swift 6.2+, tvOS 26.0+ / iOS 26.0+ deployment target (latest APIs, Liquid Glass, newest SwiftUI)
- SwiftUI for all views, UIKit only for AVPlayer wrapping
- Use Swift concurrency (async/await, actors) — no Combine
- TCA for state management (1.x with @Reducer macro)
- Tests use XCTest (not Swift Testing yet — TCA doesn't fully support it)
- All models are `Sendable`
- No force unwraps in production code

### Naming
- Types: PascalCase (ParsedChannel, M3UParser)
- Functions/variables: camelCase
- Test methods: `test[What]_[condition]_[expected]` or `test[What]_[expected]`
- Fixtures/mocks in Tests/ directory, not Sources/

### File Organization
- One type per file for models
- Parser + related helpers can share a file
- Group by feature, not by layer (e.g. Sources/M3UParser/ not Sources/Parsers/)

## Key Design Spec Sections (for reference)
When you need specifics, read docs/app-design-v2.html:
- §01: Tech stack table with all libraries
- §02: Architecture diagram + playback capability matrix + fallback policy
- §04b: Empty/degraded state definitions (8 states)
- §05: tvOS focus restoration rules (7 navigation events)
- §06: Complete database schema with identity strategy (using GRDB.swift for Swift-first phase)
- §07: Roadmap with phase exit criteria
- §08: Feature entitlement matrix (free vs premium)
- §09a: Legal compliance posture (App Store survival)
- §10: NFR targets + measurement methodology + chaos tests
- §11: Event dictionary with PII rules

## Non-Goals (do not build)
- No provider marketplace/discovery
- No DVR/recording
- No transcoding
- No external subtitle downloads (OpenSubtitles etc.)
- No Chromecast/DLNA (AirPlay only in MVP)

## Important Constraints
- tvOS memory limit: <450MB peak. Apps get killed above ~500MB.
- EPG files can be 50-200MB. Must use incremental parsing, never load into memory.
- IPTV streams are unreliable. Always implement reconnect logic.
- Never log stream URLs, channel names, or provider info (PII risk).
- Legal disclaimer must be shown on first launch before any other screen.
- No demo/sample playlists shipped — App Store reviewers reject this.
