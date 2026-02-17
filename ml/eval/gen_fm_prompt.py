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

# Genre-anchored examples — one per bucket, matched to each track's primary genre.
# Abstract: no artist/song/album names so the model can't copy content verbatim.
# These ride through to the writing step via the "example" JSONL field.
GENRE_EXAMPLES = {
    "Latin": (
        "[Facts]\n"
        "1. Samples a 1970s salsa classic.\n"
        "2. Opens the album as a tribute to the artist's musical roots.\n"
        "[End of Facts]\n"
        "Built on a 1970s salsa classic, sampled and reborn on this "
        "homeland-centered album."
    ),
    "Hip-Hop/Rap": (
        "[Facts]\n"
        "1. Samples a soul track from the 1960s.\n"
        "2. Fourth diss track, released less than 24 hours after the previous one.\n"
        "[End of Facts]\n"
        "Layers a 1960s soul sample underneath the fourth salvo in the beef — "
        "dropped less than a day after the last one."
    ),
    "Pop": (
        "[Facts]\n"
        "1. The lead single for the artist's upcoming album.\n"
        "2. Blends two genres in an unexpected way.\n"
        "[End of Facts]\n"
        "The lead single blends two unlikely genres into something fresh, "
        "setting the tone for the album ahead."
    ),
    "Country": (
        "[Facts]\n"
        "1. A bluesy ballad about the power of love.\n"
        "2. Hit #1 after a surprise awards show duet.\n"
        "[End of Facts]\n"
        "A bluesy ballad about the power of love that hit #1 "
        "after a surprise duet at a major awards show."
    ),
    "R&B/Soul": (
        "[Facts]\n"
        "1. Samples a track that inspired the song's title.\n"
        "2. The latest in a series of collaborations between two frequent partners.\n"
        "[End of Facts]\n"
        "The latest collaboration between two frequent partners, built on a "
        "sample that gave the song its name."
    ),
}

# Map variant genre labels to the five main buckets
GENRE_BUCKET = {
    "Latin": "Latin",
    "Urbano latino": "Latin",
    "Regional Mexican": "Latin",
    "Hip-Hop/Rap": "Hip-Hop/Rap",
    "Pop": "Pop",
    "Singer/Songwriter": "Pop",
    "K-Pop": "Pop",
    "Country": "Country",
    "R&B/Soul": "R&B/Soul",
}
# Fallback for Alternative, Indie Rock, J-Pop, Rock, etc.
FALLBACK_EXAMPLE = (
    "[Facts]\n"
    "1. A breakthrough single released long after the album.\n"
    "2. Explores themes of personal change.\n"
    "[End of Facts]\n"
    "A breakthrough single that arrived long after the album, "
    "exploring themes of personal change."
)


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
    mk = entry.get("musickit", {})

    # Genre: use first primary genre from MusicKit song data
    song_genres = mk.get("song", {}).get("genres", [])
    genre = next((g for g in song_genres if g != "Music"), "Unknown")

    # Assemble context (MusicKit + Genius)
    mk_ctx = build_musickit_context(mk)
    g_ctx = build_genius_context(entry.get("genius", {}))

    # Check for rich signals beyond just genre/date
    has_editorial = bool(mk.get("album", {}).get("editorialNotesShort"))
    has_genius = g_ctx is not None
    if not has_editorial and not has_genius:
        return None  # Only genre + release date — model will hallucinate

    if mk_ctx and g_ctx:
        context = mk_ctx + "\n" + g_ctx
    elif mk_ctx:
        context = mk_ctx
    else:
        context = g_ctx

    # Final prompt — task-first, genre anchor, no track/artist/album
    task = "Write a short liner note using only the facts below."
    prompt = f'{task}\n\nGenre: {genre}\n\n[Context]\n{context}\n[End of Context]'

    return {"prompt": prompt}


def main():
    entries = [json.loads(line) for line in INPUT.read_text().split("\n") if line.strip()]
    results = [build_prompt(e) for e in entries]
    skipped = results.count(None)
    results = [r for r in results if r is not None]

    with OUTPUT.open("w") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"Wrote {len(results)} prompts to {OUTPUT} (skipped {skipped} thin-context tracks)")


if __name__ == "__main__":
    main()
