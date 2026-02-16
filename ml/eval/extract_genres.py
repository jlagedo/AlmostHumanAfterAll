#!/usr/bin/env python3
"""Extract unique genres from context_top100.jsonl and show distribution."""

import json
from collections import Counter
from pathlib import Path

DATA_DIR = Path(__file__).parent.parent / "data"
INPUT = DATA_DIR / "context_top100.jsonl"
OUTPUT = DATA_DIR / "eval_output" / "genres.json"

entries = [json.loads(line) for line in INPUT.read_text().split("\n") if line.strip()]

# Collect all genre sources per track
rows = []
for e in entries:
    mk = e.get("musickit", {})
    song_genres = [g for g in mk.get("song", {}).get("genres", []) if g != "Music"]
    artist_genres = mk.get("artist", {}).get("genres", [])
    primary = song_genres[0] if song_genres else "Unknown"

    rows.append({
        "track": e["track"],
        "artist": e["artist"],
        "primary_genre": primary,
        "song_genres": song_genres,
        "artist_genres": artist_genres,
    })

# Count primary genres
primary_counts = Counter(r["primary_genre"] for r in rows)

# Count all song genres (multi-genre tracks)
all_song_genres = Counter(g for r in rows for g in r["song_genres"])

# Count artist genres
all_artist_genres = Counter(g for r in rows for g in r["artist_genres"])

print("=== Primary genre (first non-Music song genre) ===")
for genre, count in primary_counts.most_common():
    print(f"  {genre:25s} {count:3d}")

print(f"\n=== All song genres (incl. multi-genre) ===")
for genre, count in all_song_genres.most_common():
    print(f"  {genre:25s} {count:3d}")

print(f"\n=== Artist genres ===")
for genre, count in all_artist_genres.most_common():
    print(f"  {genre:25s} {count:3d}")

# Save full detail
output = {
    "primary_distribution": dict(primary_counts.most_common()),
    "all_song_genres": dict(all_song_genres.most_common()),
    "artist_genres": dict(all_artist_genres.most_common()),
    "tracks": rows,
}

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with OUTPUT.open("w") as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(f"\nFull detail written to {OUTPUT}")
