# CLAUDE.md

macOS menu bar app that delivers Apple Intelligence commentary on the music you're listening to. Uses Apple's on-device 3B Foundation Model, fine-tuned with a LoRA adapter trained on music metadata.

## Repository Structure

```
app/          Swift/Xcode — macOS menu bar app (Apple Intelligence, on-device)
ml/           Python — prompt engineering, evaluation, LoRA training for the 3B model
docs/         Shared reference material (Apple FM specs, prompt guides, training notes)
.claude/      Skills and local settings
```

`app/` and `ml/` are fully independent workspaces — each has its own `CLAUDE.md` with detailed guidance. They connect through the model: `ml/` iterates on prompts and fine-tuning, `app/` ships the results on-device via `FoundationModels` framework.

## Architecture

**Data flow:** Apple Music track change → `MusicListener` (DistributedNotificationCenter) → `MusicCoordinator.handleTrackChange()` → scrobble state machine (play/pause/stop → `ScrobbleTracker` timing → `LastFmService` submission) runs in parallel with → `TrackGatekeeper` filters duplicates/skips → `FicinoCore.process()` (prewarm + metadata fetch in parallel → `PromptBuilder` formats into `[Section]...[End Section]` blocks → `AppleIntelligenceService` generates commentary via `LanguageModelSession` + LoRA adapter) → entry saved to history → artwork fetched via MusicKit catalog search → `AppState` updated via callback → floating `NSPanel` notification shown.

**Pattern:** MVVM with coordinator. `AppState` is the single `@StateObject` for views. `MusicCoordinator` (`@MainActor`) owns all services (`MusicListener`, `FicinoCore`, `HistoryStore`, `NotificationService`, `LastFmService`, `ScrobbleTracker`) and pushes state updates to `AppState` via a `StateUpdate` enum callback. Services start eagerly at init. `CommentaryService` is dependency-injected into `FicinoCore`.

### App Targets

| Target | Description |
|---|---|
| **Ficino** | Menu bar app (UI, state, notifications) |
| **FicinoCore** | Swift package — orchestrates metadata fetch → commentary generation |
| **MusicModel** | Swift package — AI layer (`CommentaryService` protocol, `AppleIntelligenceService`) |
| **MusicContext** | Swift package — metadata providers (`MusicKitProvider`, `GeniusProvider`, `PromptBuilder`) |
| **MusicTracker** | Swift package — Last.fm integration (`LastFmService`, `ScrobbleTracker`, `ScrobbleService` protocol) |
| **MusicContextGenerator** | GUI + CLI testing tool for metadata fetch (`-p mk\|g <Artist> <Album> <Track>`) |
| **FMPromptRunner** | CLI tool for ML eval pipeline — runs prompts through on-device model |

### LoRA Adapter

`app/ficino_music.fmadapter/` — rank 32, speculative decoding (5 tokens). Current best instruction version: `ml/prompts/fm_instruction_v18.json` (13.9/15 score, zero failure flags).

### FoundationModels Session Lifecycle

Apple manages model resources at the OS level — `SystemLanguageModel` and `LanguageModelSession` are lightweight and don't need to be singletons. Creating a new session per request is the intended pattern for single-turn interactions. However, `prewarm()` is **session-scoped**: the prewarmed session must be the same instance passed to `respond()`. `AppleIntelligenceService` stores the prewarmed session and consumes it in `generate()`.

## Build

From repo root:

```sh
# Main app
xcodebuild -project app/Ficino.xcodeproj -scheme Ficino -derivedDataPath ./build build

# Metadata testing tool
xcodebuild -project app/Ficino.xcodeproj -scheme MusicContextGenerator -derivedDataPath ./build build
```

Build output: `./build/Build/Products/Debug/Ficino.app`

## ML Workflows

Uses **uv** for package management (Python 3.14+). Always run with `uv run`:

### Eval Pipeline
```sh
cd ml && uv run python eval/run_eval.py v18 -l 10
```
Steps: `build_prompts.py` (context → JSONL prompts) → `run_model.sh` (invokes FMPromptRunner) → `judge_output.py` (LLM-as-judge scoring via Claude Sonnet, 5 dimensions, max 15 pts).

**Do NOT run `judge_output.py` from within Claude Code** — it calls `claude -p` and cannot be nested.

### Training Pipeline
Synthetic training data via Anthropic Batch API: `batch_submit.py` → `batch_retrieve.py` → `join_batches.py` → `quality_check.py` → `prep_splits.py`.

See `ml/docs/` for detailed guides: `eval_pipeline.md`, `training_pipeline.md`, `lora_training_guide.md`, `data_selection_strategy.md`.

## Key Constraints

- **macOS 26+ only.** Verify API availability on macOS — do not assume iOS availability. `SystemMusicPlayer` (MusicKit) is explicitly unavailable on macOS.
- **Never modify `.pbxproj` or any file inside `.xcodeproj`** — Xcode 16+ synchronized folders auto-detect file changes on disk. For structural changes (targets, build settings, frameworks), use Xcode GUI.
- **Swift 6.2** with strict concurrency. All services use actor isolation (`FicinoCore`, `MusicContextService`, `MusicKitProvider`, `GeniusProvider`, `MusicBrainzProvider`, `RateLimiter`, `HistoryStore`, `LastFmService` are actors; `AppState`, `MusicCoordinator`, and `NotificationService` are `@MainActor`).
- **App sandbox enabled** with `com.apple.security.network.client` and `com.apple.developer.foundation-model-adapter` entitlements.
- **No test suite.** MusicModel and MusicContext have test targets but only stubs. Testing is manual via build and run.

## Secrets

Copy `app/Secrets.xcconfig.template` to `app/Secrets.xcconfig` and fill in the values. This file is gitignored.

- `GENIUS_ACCESS_TOKEN` — Genius API token (required for enriched metadata)
- `LASTFM_API_KEY` — Last.fm API key (required for scrobbling)
- `LASTFM_SHARED_SECRET` — Last.fm shared secret (required for scrobbling)

## Reference Docs (`docs/`)

### Project
- `ficino.md` — Product overview, competitive landscape, cost structure
- `preprocessing_strategies.md` — MusicKit + Genius API schemas, extraction and compression strategies
- `ficino_prompt_design.md` — **Historical:** early prompt architecture analysis and proposal (pre-LoRA)
- `lora_training_plan.md` — **Historical:** original training plan (actual training diverged — 3k samples, plain text, MusicKit+Genius)
- `music_context_pipeline.md` — **Historical:** early Fase 2 pipeline design (never implemented; app uses MusicKit+Genius, not Wikipedia/Wikidata/Last.fm)

### Apple FM Reference
- `apple_fm_specs.md` — Apple Intelligence Foundation Models technical specification
- `3b_all.md` — Complete technical guide to the on-device 3B model
- `3b_prompt_guide.md` — Prompt engineering guide for the 3B model
- `3b_lora_training.md` — LoRA adapter training system (architecture, toolkit, Swift integration)
- `3b_safety_filters.md` — Safety guardrail architecture, filter configs, false positives, Ficino impact
- `apple_adapter_toolkit.md` — Adapter Training Toolkit v26.0.0 deep reference

### Working Notes
- `musickit_api_samples.md` — Raw MusicKit API output samples (Billie Jean, Bohemian Rhapsody)
- `widget_plan.md` — Widget feature planning
- `runpod_ssh_setup.md` — RunPod SSH and file transfer setup
- `scratch.md` — Scratchpad (model output samples)
- `testing_flow.md` — Testing commands

## Skills

- **`iterate-prompt`** — Workflow for tuning FM instruction prompts and evaluating results. Invoke with `/iterate-prompt`.

## Swift & macOS Best Practices

Follow these when writing or modifying Swift code in the app.

### Concurrency & Isolation
- **Actors for shared mutable state.** Any service that manages state across async boundaries should be an `actor`. Prefer actor isolation over manual locks or `DispatchQueue`.
- **`@MainActor` for UI-bound types only.** `AppState`, view models, and anything touching AppKit/SwiftUI goes on `@MainActor`. Everything else stays off the main thread.
- **`async let` for parallel work.** When multiple independent async calls exist (e.g., MusicKit + Genius), launch them with `async let` and `await` together — not sequentially.
- **Check `Task.isCancelled` at meaningful checkpoints.** Before expensive work and before updating UI state. Use `guard !Task.isCancelled else { return }` — don't ignore cancellation.
- **Cancel stale work.** When a new operation replaces an old one (e.g., new track arrives), cancel the in-flight task first.
- **All protocols crossing isolation boundaries must be `Sendable`.** This is enforced by Swift 6.2 strict concurrency — no exceptions.

### Architecture & Design
- **Protocol-first for service boundaries.** Define protocols (`CommentaryService`, `MusicContextProvider`) for anything that could have alternate implementations or needs testability. Inject via constructor.
- **Fail gracefully, not fatally.** Optional data sources (metadata, artwork) should degrade — return `nil` and continue rather than propagating errors that abort the operation. Only hard-fail for truly unrecoverable conditions.
- **Errors as enums with `LocalizedError`.** Use typed error enums (e.g., `FicinoError`) with descriptive cases. Avoid `String`-based errors or bare `NSError`.
- **Value types by default.** Use `struct` unless you need reference semantics or actor isolation. Enums for fixed sets of cases.
- **Keep models dumb.** Data types (`TrackInput`, `CommentaryRecord`) should be plain `Struct`/`Codable` — no business logic.

### SwiftUI & AppKit
- **Single source of truth.** One `@StateObject` / `@Observable` at the top, passed down via `@EnvironmentObject` or environment. Don't duplicate state across views.
- **Decompose views.** Extract reusable subviews (`HistoryEntryView`, `FloatingNotificationView`) rather than building monolithic view bodies.
- **`NSPanel` / `NSWindow` for system-level UI.** Floating notifications, menu bar extras, and overlays use AppKit windowing. Wrap SwiftUI content in `NSHostingController`.
- **Animate with value bindings.** Use `.animation(.spring(), value: someState)` rather than implicit `.animation()` — explicit value binding prevents unexpected animation propagation.
- **`@Published` + `didSet` for UserDefaults.** Preferences pattern: `@Published var pref: T { didSet { UserDefaults.standard.set(...) } }`.

### Swift Packages & Module Boundaries
- **One responsibility per package.** `MusicModel` = AI layer, `MusicContext` = metadata, `MusicTracker` = Last.fm scrobbling, `FicinoCore` = orchestration. Don't leak concerns across package boundaries.
- **Dependencies flow downward.** `FicinoCore` depends on `MusicModel` + `MusicContext` + `MusicTracker` (re-exported for the app target). Neither leaf packages depend on each other or on `FicinoCore`.
- **Platform minimums in Package.swift.** Always set `.macOS(.v26)` (or the correct minimum). Don't omit platform constraints.

### macOS-Specific
- **Verify API availability on macOS.** Many MusicKit and system APIs differ between iOS and macOS. Always check macOS docs — don't assume iOS parity.
- **`DistributedNotificationCenter` for system events.** macOS uses this for inter-process notifications (e.g., Apple Music track changes). This is unavailable on iOS.
- **No `SystemMusicPlayer` on macOS.** MusicKit's `SystemMusicPlayer` is iOS-only. Use catalog search (`MusicCatalogSearchRequest`) for metadata lookups.
- **`LSUIElement` for menu bar apps.** Set `Application is agent (UIElement)` = YES in Info.plist to hide the dock icon.
- **App Sandbox entitlements.** Only request what you need: `com.apple.security.network.client` for outbound network, specific entitlements for framework access.

## Do NOT

- Modify `.pbxproj` or files inside `.xcodeproj` — synchronized folders handle this.
- Use few-shot examples in instruction files — the 3B model copies them verbatim as fact.
- Run `judge_output.py` inside Claude Code — it calls `claude -p` and cannot be nested.
- Delete previous instruction versions — keep them for comparison.
- Modify Swift files from the `ml/` workflow or Python files from the `app/` workflow — the workspaces are independent.
