# Ficino

A macOS menu bar app that delivers AI-generated music commentary when songs play in Apple Music, powered entirely by on-device Apple Intelligence. Named after [Marsilio Ficino](https://en.wikipedia.org/wiki/Marsilio_Ficino), the Renaissance philosopher who believed music was a bridge between the physical and divine.

Worst case, it's the most educational toy ever built.

When a track changes, Ficino fetches rich metadata (MusicKit, Genius), assembles a structured prompt, sends it to Apple's on-device 3B foundation model, and shows a floating notification with album art and its take on the song. It also scrobbles to Last.fm with play-time tracking and syncs favorites with loved tracks. No AI API calls at runtime, no subscription, no data leaving the machine (except optional Last.fm scrobbling).

Ficino is a music obsessive who lives for the story behind the song — the failed session that produced a masterpiece, the personal feud that shaped a lyric, the borrowed chord progression that changed a genre.

## Repository layout

```
app/                    macOS menu bar app (Swift / Xcode)
├── Ficino/                 App target — menu bar UI, state, track listener, notifications
├── FicinoCore/             Orchestration: track change → metadata fetch → prompt → commentary
├── MusicModel/             AI layer (CommentaryService protocol, Apple Intelligence backend)
├── MusicContext/           Metadata providers (MusicKit, Genius, MusicBrainz)
├── MusicTracker/           Last.fm integration (scrobbling, loved tracks, auth)
├── MusicContextGenerator/  Standalone GUI/CLI for testing metadata providers
├── FMPromptRunner/         Headless CLI — runs prompts through the on-device model for eval
└── Ficino.xcodeproj

ml/                     Prompt engineering, evaluation, and training (Python / uv)
├── prompts/                18 versioned instruction files (v1–v18)
├── eval/                   Eval pipeline: scrape context, build prompts, run model, LLM judge
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
5. **Display** — a custom floating `NSPanel` slides in with album art and commentary
6. **Scrobble** — play time is tracked; after 50% or 240s the track is scrobbled to Last.fm

The app is a pure menu bar app (no Dock icon). It stores a history of the last 200 commentaries with compressed thumbnails. Favorites sync bidirectionally with Last.fm loved tracks.

### The ML workspace

Iterates on the system prompt and evaluates output quality, decoupled from the app:

1. **`eval/build_prompts.py`** — mirrors the app's `PromptBuilder.swift` logic to assemble eval prompts from raw metadata
2. **`eval/run_model.sh`** — invokes `FMPromptRunner` (the Swift CLI) to run prompts through the actual on-device model
3. **`eval/judge_output.py`** — LLM-as-judge evaluation using Anthropic's API, scoring on 5 dimensions (faithfulness, grounding, tone, conciseness, accuracy — max 15 points)
4. **`eval/run_eval.py`** — end-to-end pipeline: build prompts → run model → judge in one command
5. **`training/batch_submit.py`** / **`batch_retrieve.py`** — generates training examples via Anthropic Batch API for LoRA fine-tuning

The two workspaces connect through prompt format parity (Python mirrors Swift exactly) and `FMPromptRunner` (Swift binary invoked by the Python eval pipeline).

## On-device quality: the LoRA fine-tuning story

Ficino's commentary comes from Apple's on-device 3B foundation model — a 2-bit quantized model that runs entirely on your Mac with zero network calls. Out of the box, a 3B model struggles with music journalism: it hallucinates artist names, prepends responses with "Sure! Here is…", misattributes songs, and echoes marketing copy verbatim.

We fixed this with a LoRA adapter trained on just 3,000 synthetic examples generated via Claude Haiku, distilled from real MusicKit + Genius metadata. The adapter was trained in ~2 hours on a single H100 GPU for under $10.

### The results

Evaluated across 81 tracks spanning Latin, Pop, Hip-Hop, Country, R&B, J-Pop, K-Pop, Indie Rock, and Alternative — scored by Claude Sonnet as LLM judge on faithfulness, grounding, tone, conciseness, and accuracy (max 15 points):

| Version | Score | Flags | What changed |
|---------|-------|-------|-------------|
| v14 (early prompt) | 10.6/15 | 26 preambles, 8 hallucinations, 7 misattributions | naive prompting |
| v17 (best prompt) | 13.0/15 | 8 preambles, 7 hallucinations, 2 misattributions | optimized prompt engineering |
| **v18 (LoRA adapter)** | **13.9/15** | **none** | 3k-sample fine-tune |

The LoRA adapter eliminated every single failure pattern — zero preambles, zero hallucinations, zero misattributions across all 81 responses. The worst response in v18 (13/15) scores higher than v17's average.

### Before and after

Same tracks, same metadata context, same prompt — base model vs LoRA adapter:

**Kenshi Yonezu — IRIS OUT** (J-Pop) · 8.3/15 → 14/15

> **v17 (base):** Here is a short description of the song "IRIS OUT" by Kenshi Yonezu: "IRIS OUT" by Kenshi Yonezu is a J-Pop song that was released on September 24th, 2025. It is a 16th CD single for Kenshi Yonezu and features the vocals of Japanese singer-songwriter Jane Doe. The song was produced and written by Kenshi Yonezu himself.

> **v18 (LoRA):** "IRIS OUT" is a J-Pop single by Kenshi Yonezu released on September 15, 2025. The track is a double A-side with "JANE DOE," featuring vocalist Utada Hikaru on the latter.

The base model hallucinated "Jane Doe" as a vocalist — it's actually the title of the B-side. The adapter knows the difference.

**SZA — Snooze** (R&B/Soul) · 9/15 → 14/15

> **v17 (base):** Here is a three-sentence description of the song "Snooze" by SZA. "Snooze" by SZA is a song about longing for love. The song was released as the eighth track on SZA's highly anticipated sophomore album, SOS, on December 9, 2022, and re-released as a single on August 25th, 2023.

> **v18 (LoRA):** "Snooze" by SZA is a love song from her 2022 album SOS where she expresses her desire to be with someone she loves deeply, longing in the bridge to be their number one. Released as the eighth track on December 9, 2022, the song was re-released as a single in August 2023 with a music video and an EP of different versions, including an acoustic remix featuring Justin Bieber.

The base model opens with robotic meta-framing ("Here is a three-sentence description"). The adapter just writes the commentary — richer, with details the base model missed entirely.

**Don Toliver — Body** (Hip-Hop/Rap) · 8.3/15 → 14/15

> **v17 (base):** Don Toliver's track "OCTANE" is a high-energy hip-hop/rap song that kicks off the second track on his fifth studio album, "OCTANE." The track is produced by frequent collaborator BNYX® and samples Justin Timberlake's "Rock Your Body."

> **v18 (LoRA):** "Body" is the second track on Don Toliver's fifth album OCTANE, an energetic hip-hop production from frequent collaborator BNYX® that samples Justin Timberlake's Rock Your Body. Released in January 2026, the song follows the opening track E85 as Toliver continues building momentum on what the album editorial describes as a revved-up project from Cactus Jack's melodic hitmaker.

The base model called the track "OCTANE" — that's the album name. The adapter correctly identifies "Body" as the track and weaves in album context naturally.

No cloud API. No network. ~3.7 seconds per response, running locally on a Mac.

### What's next: speculative decoding

Apple's adapter toolkit supports training a companion **draft model** — a tiny 48M parameter model (~60x smaller than the 3B) that learns to mimic the fine-tuned model's output distribution. At inference time, the draft model rapidly proposes 4-8 candidate tokens, and the full 3B verifies them all in a single forward pass. Accepted candidates become output tokens for free; rejected ones fall back to normal generation.

This is **speculative decoding**: it trades 186MB of memory for a 2-4x inference speedup with mathematically identical output quality. The 3B always has final say — the draft model only proposes, never decides.

Projected impact on Ficino's response latency:

| | Current | With draft model (conservative) | With draft model (typical) |
|---|---|---|---|
| Per response | 3.7s | ~1.8s | ~1.2s |

Combined with the full 17k training dataset (currently only 3k samples used), the next iteration should push tone scores higher while cutting latency to near-instant.

## Tech stack

**App:** Swift 6.2, SwiftUI, FoundationModels (Apple Intelligence 3B), MusicKit, DistributedNotificationCenter, NSPanel (custom floating notifications), Last.fm API (scrobbling + loved tracks). Zero third-party dependencies — pure Apple frameworks + Last.fm REST API.

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

**Optional:** copy `app/Secrets.xcconfig.template` to `app/Secrets.xcconfig` and fill in credentials:

```
GENIUS_ACCESS_TOKEN = your_token_here
LASTFM_API_KEY = your_lastfm_api_key_here
LASTFM_SHARED_SECRET = your_lastfm_shared_secret_here
```

Without the Genius token, Genius context is silently skipped (MusicKit-only). Without Last.fm credentials, scrobbling is disabled.

### ML workspace

```sh
cd ml
uv run python eval/run_eval.py v18              # full pipeline: build → run → judge
uv run python eval/run_eval.py v18 -l 10 -p 3   # limit 10, 3-pass judging
```

## Requirements

- macOS 26+ with Apple Intelligence enabled
- Apple Developer subscription (MusicKit entitlement)
- Apple Music subscription
- Xcode 16+ (for building)
- Python 3.14+ and uv (for `ml/`)
