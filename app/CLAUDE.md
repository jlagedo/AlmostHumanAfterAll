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

**Requirements:** macOS 26+, Xcode 16+, Apple Music.

**No test suite exists.** MusicModel and MusicContext have test targets but only stubs. Testing is manual via build and run.

## Source Layout

```
Ficino/                  App target (menu bar UI)
├── Models/                AppState, TrackInfo, PreferencesStore, CommentaryRecord+AppKit, Tips
├── Services/              MusicCoordinator, MusicListener, NotificationService, SettingsWindowController
└── Views/                 MenuBarView, NowPlayingView, HistoryView, SettingsView

FicinoCore/              Orchestration package
├── FicinoCore.swift       Actor: process(TrackRequest) → CommentaryResult
├── TrackGatekeeper.swift  Skip/duplicate filtering logic
├── HistoryStore.swift     SwiftData-backed history persistence (ModelActor)
├── withTimeout.swift      Async timeout utility
└── Models/                TrackRequest, CommentaryResult, CommentaryRecord, FicinoError

MusicModel/              AI layer package
├── Protocols/             CommentaryService protocol
├── Providers/             AppleIntelligenceService (FoundationModels wrapper)
└── Models/                TrackInput

MusicContext/            Metadata providers package
├── MusicContextService    Coordinates MusicKit + Genius lookups (parallel, both non-fatal)
├── PromptBuilder          Assembles metadata into [Section]...[End Section] blocks
├── Providers/             MusicKitProvider, GeniusProvider, MusicBrainzProvider
├── Models/                SongMetadata, MetadataResult, MusicBrainsData, API response types
└── Networking/            RateLimiter

MusicContextGenerator/   Standalone testing app (GUI + CLI mode)

FMPromptRunner/          CLI tool for ML eval pipeline (reads JSONL file, runs FoundationModels)

ficino_music.fmadapter/  LoRA adapter metadata (rank 32, speculative decoding: 5 tokens)
```

## Architecture

**Pattern:** MVVM with coordinator. `AppState` is the single `@StateObject` for views. `MusicCoordinator` (`@MainActor`) owns all services and pushes state updates to `AppState` via a `StateUpdate` enum callback. Views never interact with services directly — they call methods on `AppState`, which delegates to `MusicCoordinator`.

**Key flow:** `MusicListener` detects track change via `DistributedNotificationCenter` → `MusicCoordinator.handleTrackChange()` → `TrackGatekeeper` filters duplicates/skips → `FicinoCore.process()` (prewarm + metadata fetch in parallel → PromptBuilder formats into section blocks → CommentaryService generates commentary → saved to HistoryStore) → artwork fetched via MusicKit catalog search → `AppState` updated via callback → floating NSPanel notification shown.

### FicinoCore

The `FicinoCore` actor is the orchestration entry point:
- Takes a `TrackRequest` and returns a `CommentaryResult` (commentary + metadata)
- Owns `TrackGatekeeper` for skip/duplicate filtering, `HistoryStore` for SwiftData persistence
- Prewarms the AI model in parallel with metadata fetch for lower latency
- Metadata fetch has a 15s timeout; commentary generation has a 30s timeout
- `CommentaryService` is dependency-injected — app passes in `AppleIntelligenceService`
- Both MusicKit and Genius lookups are non-fatal — commentary still generates with basic track info

### MusicModel

- `CommentaryService` protocol — interface for AI backends
- `AppleIntelligenceService` — `FoundationModels` wrapper (`LanguageModelSession`)
- `TrackInput` — normalized track data passed to the LLM (includes optional `context` for enriched metadata)

### MusicContext

Three metadata providers coordinated by `MusicContextService`:
- **MusicKitProvider** — Apple MusicKit catalog search with smart matching (exact → fuzzy → fallback). Full relationships (albums, artists, composers, genres, audio variants).
- **GeniusProvider** — Genius API with rate limiting (5 req/sec). Songwriting credits, producer info, song descriptions, relationship data (samples, covers, interpolates).
- **MusicBrainzProvider** — MusicBrainz API with rate limiting (1 req/sec). Tags, genres, ISRC, community rating, release info, record labels. Used by MusicContextGenerator for batch data extraction.

`PromptBuilder` formats fetched metadata into `[Section]...[End Section]` blocks (Song, TrackDescription, ArtistBio, Album Editorial, Artist Editorial, Samples Used, Sampled By).

**MusicContextGenerator** can run as GUI or CLI: `-p mk|g|mb <Artist> <Album> <Track>`, `-p mk --id <CatalogID>`, `-p mk --playlist <Name>`, `-p mk --charts`, or `-ce <csv> [--skip N]` for batch context extraction.

### FMPromptRunner

CLI tool used by the ML eval pipeline (`ml/eval/run_model.sh`). Takes three file arguments: `<prompts.jsonl> <instructions.json> <output.jsonl>`. Supports `-l N` (limit) and `-t TEMP` (temperature) flags. Loads the LoRA adapter from bundle if present. Part of the Xcode project (not a Swift package).

### Notifications

Custom floating `NSPanel` windows (not system UNUserNotificationCenter), hosted with SwiftUI content via `NSHostingController`. Glass effect background (`.glassEffect(.regular)`), configurable position (4 corners), slide-in/out animations, drag-to-dismiss gesture, tap-to-dismiss, and auto-dismissed after a configurable duration. Avoids system permission prompts, full control over styling/positioning.

## Xcode Project Rules

- **NEVER modify `.pbxproj` or any file inside `.xcodeproj`** — the project uses Xcode 16+ synchronized folders (`PBXFileSystemSynchronizedRootGroup`), so creating/editing/deleting Swift files on disk is automatically picked up by Xcode.
- For structural changes (new targets, build settings, frameworks, build phases), instruct the user to do it manually in Xcode.

## Platform

**macOS-only.** Before using any Apple framework API, verify it is available on macOS — do not assume iOS availability implies macOS availability. Notable example: `SystemMusicPlayer` (MusicKit) is explicitly unavailable on macOS.

## Secrets

Genius API requires a token. Copy `Secrets.xcconfig.template` to `Secrets.xcconfig` and fill in `GENIUS_ACCESS_TOKEN`. This file is gitignored.

## Key Details

- App sandbox **enabled** with `com.apple.security.network.client` and `foundation-model-adapter` entitlements
- `FicinoApp.swift` is the `@main` entry using `MenuBarExtra` scene API
- MusicKit authorization requested at startup for catalog search
- Album artwork from MusicKit catalog search (URL-based, loaded via URLSession)
- History capped at 200 entries (SwiftData via `HistoryStore` actor) with JPEG-compressed thumbnails (48pt, 0.7 quality). Capacity enforcement evicts oldest non-favorited entries.
- System prompt and personality are defined in the ML workspace instruction files (`ml/prompts/fm_instruction_v*.json`), shipped via the LoRA adapter
- **Preferences** via `UserDefaults` (`PreferencesStore`): `isPaused`, `skipThreshold`, `notificationDuration`, `notificationsEnabled`, `notificationPosition` (topRight/topLeft/bottomRight/bottomLeft)
- Skip threshold: only generates commentary for tracks played longer than threshold
- `TrackGatekeeper` (struct in FicinoCore) handles duplicate detection and skip threshold logic
- All services use **actor isolation** for thread safety
- `AppState`, `MusicCoordinator`, and `NotificationService` are `@MainActor`-isolated
- `SettingsWindowController` manages a standalone `NSWindow` for settings, toggling activation policy between `.regular` and `.accessory`
