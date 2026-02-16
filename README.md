# Ficino

A music commentary system: a macOS menu bar app powered by on-device Apple Intelligence, plus a Python workspace for prompt engineering, evaluation, and LoRA fine-tuning of the underlying model.

## What it does

When a song starts playing in Apple Music, Ficino catches the track change, looks up rich metadata via MusicKit (genres, composers, editorial notes, similar artists), generates a commentary via on-device Apple Intelligence, and shows a custom floating notification with album artwork and its take on the song.

Ficino is a music obsessive who lives for the story behind the song — the failed session that produced a masterpiece, the personal feud that shaped a lyric, the borrowed chord progression that changed a genre.

## Repository Layout

```
app/               macOS menu bar app (Swift / Xcode)
├── Ficino/            App source (MVVM: Models, Services, Views)
├── Ficino.xcodeproj   Xcode project
├── FicinoCore/        Orchestration: MusicKit → prompt enrichment → commentary
├── MusicModel/        AI layer (CommentaryService protocol, Apple Intelligence backend)
├── MusicContext/      Metadata providers (MusicBrainz, MusicKit, Genius)
└── MusicContextGenerator/  Standalone tool for testing metadata providers

ml/                Prompt engineering, evaluation, and training (Python)
├── prompts/           Prompt templates and variations
├── eval/              Evaluation scripts and benchmarks
├── training/          LoRA fine-tuning pipelines
├── data/              Datasets (not tracked in git)
└── pyproject.toml

docs/              Shared documentation (Apple FM specs, prompt guides, etc.)
```

## Building the App

Open `app/Ficino.xcodeproj` in Xcode and build, or from the command line:

```sh
xcodebuild -project app/Ficino.xcodeproj -scheme Ficino -derivedDataPath ./build build
```

To build the metadata testing tool:

```sh
xcodebuild -project app/Ficino.xcodeproj -scheme MusicContextGenerator -derivedDataPath ./build build
```

## ML Workspace

```sh
cd ml
python -m venv .venv && source .venv/bin/activate
pip install -e .
```

## Tech Stack

**App:** Swift, SwiftUI, FoundationModels (Apple Intelligence), MusicKit, DistributedNotificationCenter, custom floating NSPanel notifications

**ML:** Python — prompt iteration, output evaluation, LoRA training against the on-device 3B model

## Requirements

- macOS 26+
- Apple Music
- Python 3.11+ (for `ml/`)
