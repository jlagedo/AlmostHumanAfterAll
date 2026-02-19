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

from lib.log import log_phase, log_ok, log_file

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
    parser = argparse.ArgumentParser(description="Prepare Apple toolkit training data.")
    parser.add_argument("input", type=Path, help="Quality-checked JSONL file")
    parser.add_argument("--eval-ratio", type=float, default=0.1,
                        help="Fraction of data to hold out for eval (default: 0.1)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for split")
    parser.add_argument("-o", "--output-dir", type=Path, default=None,
                        help="Output directory (default: ml/data/training/<timestamp>)")
    args = parser.parse_args()

    log_phase("Preparing training splits")

    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir or DATA_DIR / "training" / ts
    out_dir.mkdir(parents=True, exist_ok=True)

    entries = []
    for line in args.input.read_text().split("\n"):
        if not line.strip():
            continue
        entries.append(json.loads(line))

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
