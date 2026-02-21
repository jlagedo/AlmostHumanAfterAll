#!/usr/bin/env python3
"""Cryptographically shuffle a JSONL file.

Uses os.urandom via secrets module — no deterministic PRNG bias, no seed
predictability. Reads all lines into memory, assigns each a random key
from the system CSPRNG, sorts by that key.

Output: <input_stem>_shuffled.jsonl in the same directory (overwritten if exists).
"""

import secrets
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_ok, log_file


def shuffle_file(input_path: Path) -> Path:
    output_path = input_path.with_stem(input_path.stem + "_shuffled")

    log_phase("Loading")
    lines = [l for l in input_path.read_text().splitlines() if l.strip()]
    log_ok(f"{len(lines)} lines from {input_path.name}")

    log_phase("Shuffling (CSPRNG)")
    # Decorate-sort-undecorate with 128-bit random keys — uniform, no modulo bias
    decorated = [(secrets.token_bytes(16), line) for line in lines]
    decorated.sort(key=lambda x: x[0])
    lines = [line for _, line in decorated]

    log_phase("Writing")
    output_path.write_text("\n".join(lines) + "\n")
    log_ok(f"{len(lines)} lines written")
    log_file(output_path)

    return output_path


if __name__ == "__main__":
    default = Path(__file__).resolve().parent.parent / "data" / "training" / "context_17k_cleaned.jsonl"
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)
    shuffle_file(path)
