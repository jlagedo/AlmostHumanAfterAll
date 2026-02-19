#!/usr/bin/env python3
"""Convert quality-checked JSONL into Apple Adapter Training Toolkit format.

Input:  checked JSONL (id, prompt, response, stop_reason)
Output: train.jsonl + eval.jsonl in ml/data/training/<timestamp>/

Each line is a JSON array:
  [{"role": "system", "content": ...}, {"role": "user", "content": ...}, {"role": "assistant", "content": ...}]

The system prompt and task prompt mirror the app's runtime values
(AppleIntelligenceService.swift) so the adapter learns in the same
context it will be used.
"""

import argparse
import json
import random
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_ok, log_info, log_file, log_timer

DATA_DIR = ROOT / "data"

SYSTEM_PROMPT = (
    "You are a world-class music journalist who writes short, descriptive song presentations.\n"
    "1. ONLY use information from the provided sections.\n"
    "2. DO NOT fabricate or alter names, titles, genres, dates, or claims.\n"
    "3. DO NOT add any information not present in the provided sections."
)

TASK_PROMPT = "Task Overview: As a world-class music journalist, present this song to the user in 3 sentences in a descriptive writing tone."


def format_row(entry: dict) -> list[dict]:
    user_content = entry["prompt"] + "\n\n" + TASK_PROMPT
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_content},
        {"role": "assistant", "content": entry["response"]},
    ]


def main():
    parser = argparse.ArgumentParser(
        description="Convert quality-checked JSONL into Apple Adapter Training Toolkit "
                    "format. Produces train.jsonl and eval.jsonl files where each line "
                    "is a JSON array of [system, user, assistant] message objects.",
        epilog="""\
examples:
  uv run python training/prep_splits.py data/synth/joined_checked.jsonl
  uv run python training/prep_splits.py data/synth/joined_checked.jsonl --eval-ratio 0.2
  uv run python training/prep_splits.py data/synth/joined_checked.jsonl --seed 123
  uv run python training/prep_splits.py data/synth/joined_checked.jsonl -o data/training/run1

output format (each line):
  [{"role": "system", ...}, {"role": "user", ...}, {"role": "assistant", ...}]""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "input", type=Path,
        help="quality-checked JSONL file — each line must have 'prompt' and "
             "'response' fields (produced by quality_check.py)",
    )
    parser.add_argument(
        "--eval-ratio", type=float, default=0.1,
        help="fraction of data to hold out for evaluation, between 0 and 1 "
             "(default: 0.1)",
    )
    parser.add_argument(
        "--seed", type=int, default=42,
        help="random seed for reproducible train/eval split (default: 42)",
    )
    parser.add_argument(
        "-o", "--output-dir", type=Path, default=None,
        help="output directory for train.jsonl and eval.jsonl "
             "(default: data/training/<timestamp>)",
    )
    args = parser.parse_args()

    if not args.input.exists():
        log_err(f"Input file not found: {args.input}")
        sys.exit(1)

    if not (0 <= args.eval_ratio <= 1):
        log_err(f"--eval-ratio must be between 0 and 1, got {args.eval_ratio}")
        sys.exit(1)

    log_phase("Preparing training splits")

    with log_timer("Split preparation"):
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        out_dir = args.output_dir or DATA_DIR / "training" / ts
        out_dir.mkdir(parents=True, exist_ok=True)

        entries = []
        for line in args.input.read_text().split("\n"):
            if not line.strip():
                continue
            entries.append(json.loads(line))
        log_info(f"Loaded {len(entries)} entries from {args.input.name}")

        random.seed(args.seed)
        random.shuffle(entries)

        split = int(len(entries) * (1 - args.eval_ratio))
        train_entries = entries[:split]
        eval_entries = entries[split:]

        for name, subset in [("train.jsonl", train_entries), ("eval.jsonl", eval_entries)]:
            path = out_dir / name
            with path.open("w") as f:
                for entry in subset:
                    f.write(json.dumps(format_row(entry), ensure_ascii=False) + "\n")

    log_ok(f"Train: {len(train_entries)}  Eval: {len(eval_entries)}")
    log_file(out_dir)


if __name__ == "__main__":
    main()
