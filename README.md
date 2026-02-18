# Ficino

A macOS menu bar app that delivers AI-generated music commentary when songs play in Apple Music, powered entirely by on-device Apple Intelligence. Named after [Marsilio Ficino](https://en.wikipedia.org/wiki/Marsilio_Ficino), the Renaissance philosopher who believed music was a bridge between the physical and divine.

When a track changes, Ficino fetches rich metadata (MusicKit, Genius), assembles a structured prompt, sends it to Apple's on-device 3B foundation model, and shows a floating notification with album art and its take on the song. No API calls at runtime, no subscription, no data leaving the machine.

Ficino is a music obsessive who lives for the story behind the song — the failed session that produced a masterpiece, the personal feud that shaped a lyric, the borrowed chord progression that changed a genre.

## Repository layout

```
app/                    macOS menu bar app (Swift / Xcode)
├── Ficino/                 App target — menu bar UI, state, track listener, notifications
├── FicinoCore/             Orchestration: track change → metadata fetch → prompt → commentary
├── MusicModel/             AI layer (CommentaryService protocol, Apple Intelligence backend)
├── MusicContext/           Metadata providers (MusicKit, Genius, MusicBrainz)
├── MusicContextGenerator/  Standalone GUI/CLI for testing metadata providers
├── FMPromptRunner/         Headless CLI — runs prompts through the on-device model for eval
└── Ficino.xcodeproj

ml/                     Prompt engineering, evaluation, and training (Python / uv)
├── prompts/                17 versioned prompt files (v1–v17)
├── eval/                   Eval pipeline: generate prompts, run model, LLM-as-judge scoring
├── training/               LoRA training data generation via Anthropic Batch API
└── data/                   Datasets — track context, assembled prompts, model outputs

docs/                   Shared reference (Apple FM specs, prompt guides, LoRA training notes)
```

## How it works

### The app

On every Apple Music track change:

1. **Listen** — `DistributedNotificationCenter` catches `com.apple.Music.playerInfo`
2. **Enrich** — MusicKit and Genius are queried in parallel for genres, editorial notes, artist bios, sample/interpolation data
3. **Build prompt** — metadata is assembled into structured `[Section]...[End Section]` blocks
4. **Generate** — the prompt is sent to Apple's on-device `FoundationModels` 3B model via `LanguageModelSession`
5. **Display** — a custom floating `NSPanel` slides in from the top-right with album art and commentary

The app is a pure menu bar app (no Dock icon). It stores a history of the last 50 commentaries with compressed thumbnails.

### The ML workspace

Iterates on the system prompt and evaluates output quality, decoupled from the app:

1. **`eval/gen_fm_prompt.py`** — mirrors the app's `PromptBuilder.swift` logic exactly to assemble eval prompts from raw metadata
2. **`eval/run_fm.sh`** — invokes `FMPromptRunner` (the Swift CLI) to run prompts through the actual on-device model
3. **`eval/rank_output.py`** — LLM-as-judge evaluation using Anthropic's API, scoring on 5 dimensions (faithfulness, grounding, tone, conciseness, accuracy — max 15 points)
4. **`training/batch_submit.py`** / **`batch_retrieve.py`** — generates gold-standard training examples via Anthropic Batch API for eventual LoRA fine-tuning of the 3B model

The two workspaces connect through prompt format parity (Python mirrors Swift exactly) and `FMPromptRunner` (Swift binary invoked by the Python eval pipeline).

## Tech stack

**App:** Swift 6, SwiftUI, FoundationModels (Apple Intelligence 3B), MusicKit, DistributedNotificationCenter, NSPanel (custom floating notifications). Zero external dependencies.

**ML:** Python 3.14+, uv, anthropic SDK, rich. Evaluation uses Claude Sonnet as judge; training data generation uses Claude Haiku via Batch API.

## Building

### App

Open `app/Ficino.xcodeproj` in Xcode and build, or:

```sh
xcodebuild -project app/Ficino.xcodeproj -scheme Ficino -derivedDataPath ./build build
```

For the metadata testing tool:

```sh
xcodebuild -project app/Ficino.xcodeproj -scheme MusicContextGenerator -derivedDataPath ./build build
```

**Optional:** create `app/Secrets.xcconfig` with a Genius API token for richer metadata. Without it, Genius context is silently skipped and the app falls back to MusicKit-only data.

```
GENIUS_ACCESS_TOKEN = your_token_here
```

### ML workspace

```sh
cd ml
uv run python eval/gen_fm_prompt.py    # generate eval prompts
./eval/run_fm.sh v17                    # run through on-device model
uv run python eval/rank_output.py       # score outputs
```

## Requirements

- macOS 26+ with Apple Intelligence enabled
- Apple Developer subscription (MusicKit entitlement)
- Apple Music subscription
- Xcode 16+ (for building)
- Python 3.14+ and uv (for `ml/`)
