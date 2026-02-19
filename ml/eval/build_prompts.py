#!/usr/bin/env python3
"""Generate FM-format prompts from a context JSONL file.

Mirrors the prompt-building logic from the Swift app:
- PromptBuilder.swift (context assembly from MusicKit + Genius metadata)
- AppleIntelligenceService.swift (final prompt format)
- Personality.swift (system instructions)

Output: one JSON object per line with { "id", "prompt" }
"""

import argparse
import json
import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_info, log_ok, log_warn, log_err, log_file, log_timer

DATA_DIR = ROOT / "data"


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


    return {"id": str(uuid.uuid4()), "prompt": "\n\n".join(sections)}


def main():
    parser = argparse.ArgumentParser(description="Generate FM-format prompts from context JSONL.")
    parser.add_argument("input", type=Path, help="Input context JSONL file")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="Output JSONL path (default: <input_stem>_prompts.jsonl in same dir)")
    parser.add_argument("-l", type=int, default=None, help="Limit number of output prompts")
    parser.add_argument("-v", "--version", type=str, default=None,
                        help="Version tag (e.g. v17) — reads prompt template from prompts/fm_instruction_<version>.json")
    args = parser.parse_args()

    output = args.output or args.input.parent / f"{args.input.stem}_prompts.jsonl"

    log_phase("Building FM prompts")

    with log_timer("Prompt building"):
        # Load prompt template from instruction file if version specified
        task_prompt = None
        if args.version:
            instruction_path = DATA_DIR.parent / "prompts" / f"fm_instruction_{args.version}.json"
            if not instruction_path.exists():
                log_err(f"Not found: {instruction_path}")
                sys.exit(1)
            instruction = json.loads(instruction_path.read_text())
            task_prompt = instruction.get("prompt")
            if task_prompt:
                log_info(f"Using prompt template from {instruction_path.name}")

        entries = []
        malformed = 0
        for line in args.input.read_text().split("\n"):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                malformed += 1
        log_info(f"Loaded {len(entries)} context entries from {args.input.name}")
        if malformed:
            log_warn(f"Skipped {malformed} malformed lines")
        results = [build_prompt(e) for e in entries]
        skipped = results.count(None)
        results = [r for r in results if r is not None]

        if task_prompt:
            for r in results:
                r["prompt"] += "\n\n" + task_prompt

        if args.l is not None:
            results = results[:args.l]

        with output.open("w") as f:
            for r in results:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")

    log_ok(f"Wrote {len(results)} prompts (skipped {skipped} thin-context tracks)")
    log_file(output)


if __name__ == "__main__":
    main()
