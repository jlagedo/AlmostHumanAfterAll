# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Ficino

A macOS menu bar app that listens to Apple Music track changes and delivers AI-powered commentary via Claude CLI or Apple Intelligence. Runs as a menu bar utility (LSUIElement=true, no dock icon). Zero external dependencies — pure Apple frameworks.

## Build & Run

Open `Ficino.xcodeproj` in Xcode, or build from CLI:

```sh
xcodebuild -project Ficino.xcodeproj -scheme Ficino -derivedDataPath ./build build
```

Build output: `./build/Build/Products/Debug/Ficino.app`

There's a second scheme **MusicContextGenerator** for the metadata testing tool:
```sh
xcodebuild -project Ficino.xcodeproj -scheme MusicContextGenerator -derivedDataPath ./build build
```

**Requirements:** macOS 14+, Claude Code CLI at `/usr/local/bin/claude`, Apple Music.

**No test suite exists.** Testing is manual via build and run.

## Architecture

**Pattern:** MVVM with a single `AppState` observable object coordinating services. Views bind to `@StateObject AppState`.

**Source layout:**
- `Ficino/Models/` — Data types and state (`AppState`, `TrackInfo`, `Personality`, `CommentEntry`, `AIEngine`)
- `Ficino/Services/` — Business logic (`MusicListener`, `ClaudeService`, `AppleIntelligenceService`, `ArtworkService`, `NotificationService`)
- `Ficino/Views/` — SwiftUI components (`MenuBarView`, `NowPlayingView`, `HistoryView`, `PersonalityPickerView`, `SettingsView`)
- `MusicContext/` — Swift package for fetching music metadata from MusicBrainz and MusicKit APIs
- `MusicContextGenerator/` — Standalone macOS app for testing MusicContext providers (GUI + CLI mode)

**Key flow:** MusicListener detects track change via `DistributedNotificationCenter` → `AppState.handleTrackChange()` → parallel artwork fetch + commentary request (`async let`) → result saved to history → floating NSPanel notification shown → every 5 songs triggers a review.

### Services

**ClaudeService** is a Swift `actor` that manages a persistent Claude CLI subprocess with JSON streaming over stdin/stdout. It handles process lifecycle, crash recovery (max 3 retries), stale response draining, and 30-second timeouts. Stale draining is critical — after cancelling an in-flight request, it waits up to 5s for the old JSON result before sending a new prompt to prevent delivering stale responses to new continuations.

**CommentaryService** is the protocol both `ClaudeService` and `AppleIntelligenceService` conform to, allowing runtime backend swapping via `AppState.engine`. Apple Intelligence requires macOS 26+ and uses the `FoundationModels` framework.

**Notifications** are custom floating `NSPanel` windows (not system UNUserNotificationCenter), hosted with SwiftUI content and auto-dismissed after a configurable duration. This avoids system permission prompts and gives full control over styling/positioning.

### MusicContext Package

`MusicContext/` is a standalone Swift package with two providers:

- **MusicBrainzProvider** — Actor wrapping MusicBrainz REST API with rate limiting (1 req/sec). Has a multi-fallback search strategy: strips Apple Music suffixes (" - EP", " (Deluxe)"), featuring credits, collaborator names to improve match rates. Multi-stage lookup: recording → tags/genres → artist details → release group → label/format.
- **MusicKitProvider** — Actor wrapping Apple MusicKit catalog search with smart matching (exact → fuzzy → fallback). Loads full relationships (albums, artists, composers, genres, audio variants).

**MusicContextGenerator** can run as GUI or CLI with arguments: `-p mb|mk <Artist> <Album> <Track> [DurationMs]` or `-p mk --id <CatalogID>`.

## Important Details

- App sandbox is **disabled** in `Ficino.entitlements` — needed for subprocess spawning, DistributedNotificationCenter, and AppleScript execution
- `FicinoApp.swift` is the `@main` entry using `MenuBarExtra` scene API
- Album artwork is fetched via AppleScript bridge to Music.app (`raw data of artwork 1 of current track`), not MusicKit
- History is capped at 50 entries with JPEG-compressed thumbnails (48pt, 0.7 quality)
- The 6 personality options each have detailed system prompts defined in `Personality.swift`; the "Claudy" personality enables WebSearch tool access
- **Preferences** persist via `UserDefaults`: personality, AI engine, model name, skip threshold, notification duration
- Skip threshold enforcement: only generates commentary for tracks played longer than the threshold, preventing spam from rapid skipping
- All services use **actor isolation** for thread safety (ClaudeService, AppleIntelligenceService, MusicBrainzProvider, MusicKitProvider, RateLimiter)
- `AppState` and `NotificationService` are `@MainActor`-isolated for UI safety
