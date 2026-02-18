#!/usr/bin/env python3
"""Generate FM-format prompts from context_top100.jsonl.

Mirrors the prompt-building logic from the Swift app:
- PromptBuilder.swift (context assembly from MusicKit + Genius metadata)
- AppleIntelligenceService.swift (final prompt format)
- Personality.swift (system instructions)

Output: data/eval_output/prompts_top100.jsonl — one JSON object per line with
  { "prompt" }
"""

import argparse
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


JUNK_PHRASES = [
    "Click here to learn how to translate",
    "Spotify is a music",
    "OVO Sound Radio",
    "Every Friday, Spotify compiles",
]


def strip_html(html: str) -> str:
    return re.sub(r"<[^>]+>", "", html)


def strip_urls(text: str) -> str:
    return re.sub(r"https?://\S+", "", text).strip()


CTA_PHRASES = [
    "Pre-add",
    "pre-add",
    "Pre-save",
    "pre-save",
    "Listen now",
    "listen now",
    "Stream now",
    "stream now",
]


def is_junk(text: str) -> bool:
    return any(phrase in text for phrase in JUNK_PHRASES)


def is_cta(text: str) -> bool:
    return any(phrase in text for phrase in CTA_PHRASES)


def build_prompt(entry: dict) -> dict | None:
    mk = entry.get("musickit") or {}
    genius = entry.get("genius") or {}
    song = mk.get("song") or {}
    album = mk.get("album") or {}
    artist_mk = mk.get("artist") or {}
    genius_track = genius.get("track") or {}
    genius_artist = genius.get("artist") or {}
    genius_trivia = genius.get("trivia") or {}

    # Filter: require TrackDescription (Tiers A/B/C only — skip D and E)
    wiki_raw = genius_track.get("wikiSummary")
    if not wiki_raw or is_junk(wiki_raw):
        return None

    sections: list[str] = []

    # Song — identity + basic metadata
    song_parts = [entry["track"], entry["artist"], entry["album"]]
    genres = [g for g in song.get("genres", []) if g != "Music"]
    if genres:
        song_parts.append(f"Genre: {', '.join(genres)}")
    release = song.get("releaseDate")
    if release:
        song_parts.append(f"Released: {release[:10]}")
    sections.append(f"[Song]\n" + "\n".join(song_parts) + "\n[End Song]")

    # Track description — position 2 (primacy); model's primary source
    wiki = genius_track.get("wikiSummary")
    if wiki and not is_junk(wiki):
        sections.append(f"[TrackDescription]\n{strip_urls(wiki)}\n[End TrackDescription]")

    # Artist bio — middle position (lowest attention on 3B)
    bio = genius_artist.get("bio")
    if bio and not is_junk(bio):
        sections.append(f"[ArtistBio]\n{strip_urls(bio)}\n[End ArtistBio]")

    # Editorial — drop blocks with marketing CTAs
    album_editorial = album.get("editorialNotesShort")
    if album_editorial and not is_cta(strip_html(album_editorial)):
        sections.append(f"[Album Editorial]\n{strip_html(album_editorial)}\n[End Album Editorial]")

    artist_editorial = artist_mk.get("editorialNotesShort")
    if artist_editorial and not is_cta(strip_html(artist_editorial)):
        sections.append(f"[Artist Editorial]\n{strip_html(artist_editorial)}\n[End Artist Editorial]")

    # Samples
    samples = genius_trivia.get("samples", [])
    if samples:
        sections.append(f"[Samples Used]\n{'; '.join(samples)}\n[End Samples Used]")

    sampled_by = genius_trivia.get("sampledBy", [])
    if sampled_by:
        sections.append(f"[Sampled By]\n{'; '.join(sampled_by)}\n[End Sampled By]")


    return {"prompt": "\n\n".join(sections)}


def main():
    parser = argparse.ArgumentParser(description="Generate FM-format prompts from context JSONL.")
    parser.add_argument("-l", type=int, default=None, help="Limit number of output prompts")
    parser.add_argument("-v", "--version", type=str, default=None,
                        help="Version tag (e.g. v17) — reads prompt template from prompts/fm_instruction_<version>.json")
    args = parser.parse_args()

    # Load prompt template from instruction file if version specified
    task_prompt = None
    if args.version:
        instruction_path = DATA_DIR.parent / "prompts" / f"fm_instruction_{args.version}.json"
        if not instruction_path.exists():
            print(f"Error: {instruction_path} not found")
            return
        instruction = json.loads(instruction_path.read_text())
        task_prompt = instruction.get("prompt")
        if task_prompt:
            print(f"Using prompt template from {instruction_path.name}")

    entries = [json.loads(line) for line in INPUT.read_text().split("\n") if line.strip()]
    results = [build_prompt(e) for e in entries]
    skipped = results.count(None)
    results = [r for r in results if r is not None]

    if task_prompt:
        for r in results:
            r["prompt"] += "\n\n" + task_prompt

    if args.l is not None:
        results = results[:args.l]

    with OUTPUT.open("w") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"Wrote {len(results)} prompts to {OUTPUT} (skipped {skipped} thin-context tracks)")


if __name__ == "__main__":
    main()
