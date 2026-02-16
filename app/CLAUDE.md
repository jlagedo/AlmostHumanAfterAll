# App — CLAUDE.md

macOS menu bar app that listens to Apple Music track changes and delivers AI-powered commentary via Apple Intelligence. Runs as a menu bar utility (LSUIElement=true, no dock icon). Zero external dependencies — pure Apple frameworks.

## Build & Run

Open `Ficino.xcodeproj` in Xcode, or build from CLI (run from repo root):

```sh
xcodebuild -project app/Ficino.xcodeproj -scheme Ficino -derivedDataPath ./build build
```

Build output: `./build/Build/Products/Debug/Ficino.app`

Second scheme **MusicContextGenerator** for the metadata testing tool:
```sh
xcodebuild -project app/Ficino.xcodeproj -scheme MusicContextGenerator -derivedDataPath ./build build
```

**Requirements:** macOS 26+, Apple Music.

**No test suite exists.** Testing is manual via build and run.

## Source Layout

```
Ficino/                  App target
├── Models/                AppState, TrackInfo, CommentEntry
├── Services/              MusicListener, NotificationService
└── Views/                 MenuBarView, NowPlayingView, HistoryView, SettingsView

FicinoCore/              Orchestration package
├── FicinoCore.swift       Single entry point actor
├── PromptBuilder.swift    Enriches TrackInput with metadata context
└── Models/                TrackRequest, TrackResult

MusicModel/              AI layer package
├── Protocols/             CommentaryService protocol
├── Providers/             AppleIntelligenceService (FoundationModels wrapper)
└── Models/                Personality, TrackInput

MusicContext/            Metadata providers package
├── Providers/             MusicBrainzProvider, MusicKitProvider, GeniusProvider
├── Models/                API response types
└── Networking/            RateLimiter

MusicContextGenerator/   Standalone testing app (GUI + CLI mode)
```

## Architecture

**Pattern:** MVVM with a single `AppState` observable object coordinating services. Views bind to `@StateObject AppState`.

**Key flow:** MusicListener detects track change via `DistributedNotificationCenter` → `AppState.handleTrackChange()` → `FicinoCore.process()` (MusicKit lookup → enriched TrackInput → commentary generation) → artwork loaded from URL → result saved to history → floating NSPanel notification shown.

### FicinoCore

The `FicinoCore` actor is the single entry point for the app:
- Takes a `TrackRequest` (notification data) and returns a `TrackResult` (commentary + artwork URL)
- Internally: MusicKit catalog search → `PromptBuilder` enriches `TrackInput` with metadata → `CommentaryService` generates commentary
- `CommentaryService` is dependency-injected — app passes in `AppleIntelligenceService`
- MusicKit failures are non-fatal — commentary still generates with basic track info

### MusicModel

- `CommentaryService` protocol — interface for AI backends
- `AppleIntelligenceService` — `FoundationModels` wrapper (`LanguageModelSession`)
- `Personality` enum — single "Ficino" personality with system prompt
- `TrackInput` — normalized track data passed to the LLM (includes optional `context` for enriched metadata)

### MusicContext

Three providers:
- **MusicBrainzProvider** — MusicBrainz REST API with rate limiting (1 req/sec). Multi-fallback search, multi-stage lookup: recording → tags/genres → artist details → release group → label/format.
- **MusicKitProvider** — Apple MusicKit catalog search with smart matching (exact → fuzzy → fallback). Full relationships (albums, artists, composers, genres, audio variants).
- **GeniusProvider** — Genius API with rate limiting (5 req/sec). Songwriting credits, producer info, song descriptions, relationship data (samples, covers, interpolates).

**MusicContextGenerator** can run as GUI or CLI: `-p mb|mk|g <Artist> <Album> <Track> [DurationMs]` or `-p mk --id <CatalogID>`.

### Notifications

Custom floating `NSPanel` windows (not system UNUserNotificationCenter), hosted with SwiftUI content, drag-to-dismiss, and auto-dismissed after a configurable duration. Avoids system permission prompts, full control over styling/positioning.

## Xcode Project Rules

- **NEVER modify `.pbxproj` or any file inside `.xcodeproj`** — the project uses Xcode 16+ synchronized folders (`PBXFileSystemSynchronizedRootGroup`), so creating/editing/deleting Swift files on disk is automatically picked up by Xcode.
- For structural changes (new targets, build settings, frameworks, build phases), instruct the user to do it manually in Xcode.

## Platform

**macOS-only.** Before using any Apple framework API, verify it is available on macOS — do not assume iOS availability implies macOS availability. Notable example: `SystemMusicPlayer` (MusicKit) is explicitly unavailable on macOS.

## Reference Docs

- `docs/apple_fm_specs.md` — Apple Intelligence Foundation Models specification (architecture, API, benchmarks, token budgets)

## Key Details

- App sandbox **enabled** with `com.apple.security.network.client` for MusicKit catalog access
- `FicinoApp.swift` is the `@main` entry using `MenuBarExtra` scene API
- MusicKit authorization requested at startup for catalog search
- Album artwork from MusicKit catalog search (URL-based, loaded via URLSession)
- History capped at 50 entries with JPEG-compressed thumbnails (48pt, 0.7 quality)
- Single personality ("Ficino") with system prompt in `Personality.swift`
- **Preferences** via `UserDefaults`: skip threshold, notification duration
- Skip threshold: only generates commentary for tracks played longer than threshold
- All services use **actor isolation** for thread safety
- `AppState` and `NotificationService` are `@MainActor`-isolated
