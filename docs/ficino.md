# Ficino

**Don't just listen. Feel.**

## What is it

A macOS companion app for Apple Music that provides real-time music insights while the user listens. It acts like a friend who's a music nerd — someone who collects music history because they love it.

## How it works

1. Detect track change via `DistributedNotificationCenter` (`com.apple.Music.playerInfo`)
2. Fetch metadata from MusicKit + Genius in parallel (both non-fatal)
3. Assemble structured prompt from metadata (`[Section]...[End Section]` blocks)
4. Generate commentary via on-device 3B model (`LanguageModelSession` + LoRA adapter)
5. Show floating `NSPanel` notification with album art and commentary
6. Scrobble to Last.fm after 50% or 240s of play time

## AI Architecture

- **Apple Foundation Models** — 3B on-device model via Swift API
- **LoRA adapter** — trained for the Ficino persona (music nerd friend tone)
- **RAG pattern** — LoRA teaches persona/style, scraped data provides facts at runtime
- **Training data** — 3,000 high-quality examples generated via Claude Haiku Batch (~$15)
- **No API costs at runtime** — fully on-device, free inference

## Competitive Landscape

- **NowPlaying** — closest competitor, featured on TechCrunch/MacRumors. It's a database browser (IMDB for music). Aggregates raw facts.
- **Ficino's moat** — AI persona. It doesn't show everything, it tells the story. The LoRA adapter *is* the differentiator.

## Cost Structure

| Item | Cost |
|---|---|
| LoRA training data (Claude Sonnet Batch) | ~$15 one-time |
| GPU rental for training (if needed) | ~$2–5 one-time |
| On-device inference | Free |
| Apple Private Cloud Compute | Free |
| Apple Developer Program | $99/year |

## Key Risks

- Apple controls the model, can change/deprecate APIs
- LoRA adapter breaks on base model updates — retrain needed
- Apple ecosystem only — no cross-platform
- PCC rate limits unknown
- 3B model quality ceiling for complex synthesis

## Name Origin

Marsilio Ficino (1433–1499) — Renaissance philosopher who believed music is a bridge between the physical and the divine. Founded the Platonic Academy in Florence. Coined "Platonic love." Played the lira da braccio and used music as philosophical therapy. The name carries the idea that music is more than sound.
