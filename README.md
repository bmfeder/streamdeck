# StreamDeck

A blazing-fast, native media player for IPTV and Emby.

**Status:** Phase 0 — Scaffolding

## Overview

Cross-platform media player built with native performance as the north star. tvOS-first design with M3U/Xtream Codes IPTV support and full Emby integration.

## Tech Stack

| Layer | Apple | Shared |
|-------|-------|--------|
| UI | SwiftUI + TCA | — |
| Video | AVPlayer + VLCKit | Player state machine |
| Parsing | — | M3U / Xtream / XMLTV |
| Storage | — | SQLDelight |
| Networking | — | Ktor |

## Project Structure

```
docs/              Design specification (open in browser)
tasks/             Phase 0 + Phase 1 task tracker
StreamDeck/        Swift Package (parsers, models, tests)
```

## Getting Started

```bash
cd StreamDeck
swift test
```

## Documentation

Open `docs/app-design-v2.html` in a browser for the full design specification including architecture, data model, roadmap, and NFR targets.
