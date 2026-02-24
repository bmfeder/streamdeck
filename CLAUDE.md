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
- **Local Storage**: SQLDelight (KMP shared DB).
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
├── docs/
│   └── app-design-v2.html    ← full design spec (open in browser to read)
├── tasks/
│   └── streamdeck-tasks.xlsx  ← Phase 0 + Phase 1 task tracker
├── StreamDeck/                ← Swift Package (M3U parser, models, tests)
│   ├── Package.swift
│   ├── Sources/M3UParser/
│   │   ├── M3UParser.swift    ← production M3U/M3U8 parser
│   │   └── Models.swift       ← ParsedChannel, M3UParseResult, etc.
│   └── Tests/M3UParserTests/
│       ├── M3UParserTests.swift  ← 38 test cases
│       └── M3UFixtures.swift     ← 20 test playlists (edge cases)
├── App/                       ← tvOS app target (to be created)
└── Shared/                    ← KMP shared module (to be created)
```

## Current Status
- **Phase 0 — In Progress**
- Design spec v2.1 complete (16 sections, reviewed twice)
- M3U parser written and tested (38 test cases, 20 fixture playlists)
- Task tracker created with Phase 0 (16 tasks) and Phase 1 (29 tasks)
- No Xcode project yet — Swift Package only

## What to Build Next (Phase 0 remaining)
Reference: tasks/streamdeck-tasks.xlsx, "Phase 0 — Scaffolding" sheet
1. Create Xcode project with tvOS target (SwiftUI lifecycle, tvOS 17.0+)
2. Add empty KMP shared module (can defer if focusing Swift-only first)
3. Configure SPM dependencies (VLCKit, TCA, SQLDelight)
4. Xtream Codes API client + unit tests with mock HTTP responses
5. XMLTV EPG parser (incremental/SAX-style) + tests
6. SQLDelight schema v1 (all tables from design spec §06)
7. TCA skeleton with sidebar navigation
8. GitHub Actions CI (build + test)
9. TestFlight setup

## Coding Conventions

### Swift
- Swift 5.9+, iOS/tvOS 17.0+ deployment target
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
- §06: Complete SQLDelight schema with identity strategy
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
