#!/usr/bin/env python3
"""Join batch API responses with their source prompts.

Produces a consolidated JSONL where each line has the full prompt
context alongside the model's generated commentary.

Output format per line:
  {"id", "prompt", "response", "stop_reason"}
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_ok, log_warn, log_file


def main():
    parser = argparse.ArgumentParser(description="Join batch responses with source prompts.")
    parser.add_argument("prompts", type=Path, help="Prompts JSONL (id + prompt)")
    parser.add_argument("responses", type=Path, help="Batch output JSONL (id + response + stop_reason)")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="Output JSONL path (default: joined_<responses_stem>.jsonl in responses dir)")
    args = parser.parse_args()

    output = args.output or args.responses.parent / f"joined_{args.responses.stem}.jsonl"

    log_phase("Joining prompts with responses")

    # Index prompts by id
    prompts = {}
    for line in args.prompts.read_text().split("\n"):
        if not line.strip():
            continue
        entry = json.loads(line)
        prompts[entry["id"]] = entry["prompt"]

    joined = 0
    missing = 0
    with output.open("w") as f:
        for line in args.responses.read_text().split("\n"):
            if not line.strip():
                continue
            entry = json.loads(line)
            rid = entry["id"]
            if rid not in prompts:
                missing += 1
                continue
            row = {
                "id": rid,
                "prompt": prompts[rid],
                "response": entry["response"],
                "stop_reason": entry.get("stop_reason", ""),
            }
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
            joined += 1

    log_ok(f"Joined {joined} rows")
    log_file(output)
    if missing:
        log_warn(f"{missing} responses had no matching prompt (skipped)")


if __name__ == "__main__":
    main()
