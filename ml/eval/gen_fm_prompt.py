#!/usr/bin/env python3
"""Generate FM-format prompts from context_top100.jsonl.

Mirrors the prompt-building logic from the Swift app:
- PromptBuilder.swift (context assembly from MusicKit + Genius metadata)
- AppleIntelligenceService.swift (final prompt format)
- Personality.swift (system instructions)

Output: data/eval_output/prompts_top100.jsonl — one JSON object per line with
  { "prompt" }
"""

import json
import re
from pathlib import Path

DATA_DIR = Path(__file__).parent.parent / "data"
INPUT = DATA_DIR / "context_top100.jsonl"
OUTPUT = DATA_DIR / "eval_output" / "prompts_top100.jsonl"


def strip_html(html: str) -> str:
    return re.sub(r"<[^>]+>", "", html)


def build_musickit_context(mk: dict) -> str | None:
    parts: list[str] = []

    song = mk.get("song", {})

    # Genres — filter to primary (same logic as Swift: first non-"Music" genre)
    genres = song.get("genres", [])
    primary = [g for g in genres if g != "Music"]
    if primary:
        parts.append(f"Genres: {', '.join(primary)}")

    # Release date
    release = song.get("releaseDate")
    if release:
        parts.append(f"Release date: {release[:10]}")

    # Editorial notes (prefer album-level standard/short, like MusicKit Song)
    album = mk.get("album", {})
    editorial_short = album.get("editorialNotesShort")
    if editorial_short:
        parts.append(f"Editorial notes: {strip_html(editorial_short)}")

    return "\n".join(parts) if parts else None


def build_genius_context(genius: dict) -> str | None:
    parts: list[str] = []
    trivia = genius.get("trivia", {})
    track = genius.get("track", {})

    samples = trivia.get("samples", [])
    if samples:
        parts.append(f"Samples: {'; '.join(samples)}")

    wiki = track.get("wikiSummary")
    if wiki:
        truncated = wiki[:250] + "..." if len(wiki) > 250 else wiki
        parts.append(f"Song description: {truncated}")

    return "\n".join(parts) if parts else None


def build_prompt(entry: dict) -> dict:
    track = entry["track"]
    artist = entry["artist"]
    album = entry["album"]

    # Genre: use first primary genre from MusicKit song data
    mk = entry.get("musickit", {})
    song_genres = mk.get("song", {}).get("genres", [])
    genre = next((g for g in song_genres if g != "Music"), "Unknown")

    # Assemble context (MusicKit + Genius)
    mk_ctx = build_musickit_context(mk)
    g_ctx = build_genius_context(entry.get("genius", {}))

    if mk_ctx and g_ctx:
        context = mk_ctx + "\n" + g_ctx
    elif mk_ctx:
        context = mk_ctx
    elif g_ctx:
        context = g_ctx
    else:
        context = None

    # Final prompt — mirrors AppleIntelligenceService.swift
    if context:
        prompt = f'"{track}" by {artist}, from "{album}" ({genre}).\n\n{context}\n\nFicino:'
    else:
        prompt = f'"{track}" by {artist}, from "{album}" ({genre}).\n\nReact.'

    return {"prompt": prompt}


def main():
    entries = [json.loads(line) for line in INPUT.read_text().split("\n") if line.strip()]
    results = [build_prompt(e) for e in entries]

    with OUTPUT.open("w") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"Wrote {len(results)} prompts to {OUTPUT}")


if __name__ == "__main__":
    main()
