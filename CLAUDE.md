# CLAUDE.md — StreamDeck Project Context

## What is this project?
StreamDeck is a cross-platform IPTV/Emby media player app, similar to KDTivi. Priority platform is tvOS (Apple TV), with iOS companion and future Android TV support.

## Architecture Decisions (locked in)

### Tech Stack
- **tvOS/iOS UI**: SwiftUI + UIKit (for AVPlayer wrapping). TCA (The Composable Architecture) for state management.
- **Android TV UI** (future): Jetpack Compose for TV (androidx.tv:tv-material). Orbit MVI.
- **Shared Logic (KMP)**: Set up from day 1 but building Swift-first for now. Will migrate parsers/models to Kotlin when Android work begins.
- **Video**: AVPlayer (primary) + VLCKit (fallback via on-demand resources). FFprobeKit for codec probing (<200ms).
- **Networking**: Ktor (KMP) — or URLSession for Swift-only phase.
- **Image Loading**: Coil Multiplatform (KMP).
- **Local Storage**: GRDB.swift (Swift-first phase). Will port schema to SQLDelight in KMP shared module for Android (Phase 4).
- **DI**: Koin (KMP).
- **Security**: Keychain for credentials. Never store passwords in SQLite.
- **Subscriptions**: StoreKit 2 (Apple-only). Add RevenueCat when Android launches.

### Architecture Pattern
Four-layer clean architecture:
1. **Presentation** — SwiftUI views, TCA reducers, tvOS focus handlers
2. **Use Cases / Repos** — PlaylistRepository, ChannelRepository, EmbyRepository, etc.
3. **Domain (Shared)** — Parsers, models, Emby API client, search
4. **Data** — SQLDelight DB, HTTP client, image cache, CloudKit sync

### Video Playback Pipeline
User selects → Resolve URL → FFprobeKit probe (<200ms) → Route to AVPlayer (HLS/MP4) or VLCKit (TS/MKV/RTSP/RTMP) → Playback. Reconnect with exponential backoff (3 retries, then fallback engine once). See capability matrix in docs/app-design-v2.html §02.

### Data Model Identity Strategy
Channels use three-tier IDs: `playlist_id` (source) → `source_channel_id` (provider-native) → `id` (app canonical). On playlist refresh, match by source_channel_id first, then tvg_id, then name+group. Update stream URLs but keep canonical ID stable. Soft-delete channels missing from refresh (purge after 30 days). This preserves favorites and watch progress across URL rotations.

## Project Structure
```
streamdeck/
├── CLAUDE.md                  ← you are here
├── StreamDeck.xcodeproj       ← Xcode project (tvOS app)
├── App/                       ← tvOS app target (SwiftUI)
│   ├── StreamDeckApp.swift
│   ├── ContentView.swift
│   └── Assets.xcassets/
├── StreamDeck/                ← Swift Package (parsers, models, tests)
│   ├── Package.swift
│   ├── Sources/M3UParser/     ← M3U/M3U8 parser (41 tests)
│   ├── Sources/XtreamClient/  ← Xtream Codes API client (57 tests)
│   ├── Sources/XMLTVParser/   ← XMLTV EPG parser, SAX-style (57 tests)
│   └── Tests/
├── Shared/                    ← KMP shared module (empty shell, for Android phase)
├── docs/
│   └── app-design-v2.html    ← full design spec (open in browser to read)
└── tasks/
    └── streamdeck-tasks.xlsx  ← Phase 0 + Phase 1 task tracker
```

## Current Status
- **Phase 0 — In Progress**
- Design spec v2.1 complete (16 sections, reviewed twice)
- M3U parser written and tested (41 tests, 20 fixture playlists)
- Xtream Codes API client written and tested (57 tests)
- XMLTV EPG parser written and tested (57 tests, SAX-style incremental)
- Xcode project created (tvOS 26.0+, SwiftUI lifecycle)
- Local Swift Package linked (M3UParser, XtreamClient, XMLTVParser)
- KMP shared module scaffolded (empty shell)
- Task tracker created with Phase 0 (16 tasks) and Phase 1 (29 tasks)

## What to Build Next (Phase 0 remaining)
Reference: tasks/streamdeck-tasks.xlsx, "Phase 0 — Scaffolding" sheet
1. Configure SPM dependencies (TCA, GRDB, VLCKit)
2. GRDB schema v1 (all tables from design spec §06)
3. TCA skeleton with sidebar navigation
4. GitHub Actions CI (build + test)
5. TestFlight setup

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
- No server-side accounts or backend
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
