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

from lib.log import log_phase, log_ok, log_warn, log_info, log_file, log_timer


def main():
    parser = argparse.ArgumentParser(
        description="Join batch API responses with their source prompts into a single "
                    "JSONL file. Each output line contains 'id', 'prompt', 'response', "
                    "and 'stop_reason' fields, ready for quality checking.",
        epilog="""\
examples:
  uv run python training/join_batches.py \\
      data/eval/prompts_top100.jsonl \\
      data/synth/batch_abc123_20250601.jsonl

  uv run python training/join_batches.py \\
      data/eval/prompts_top100.jsonl \\
      data/synth/batch_abc123_20250601.jsonl \\
      -o data/synth/joined.jsonl""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "prompts", type=Path,
        help="prompts JSONL file — each line must have 'id' and 'prompt' fields "
             "(produced by build_prompts.py)",
    )
    parser.add_argument(
        "responses", type=Path,
        help="batch output JSONL file — each line must have 'id', 'response', and "
             "'stop_reason' fields (produced by batch_retrieve.py)",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=None,
        help="output JSONL path (default: joined_<responses_stem>.jsonl in the "
             "responses directory)",
    )
    args = parser.parse_args()

    if not args.prompts.exists():
        log_err(f"Prompts file not found: {args.prompts}")
        sys.exit(1)

    if not args.responses.exists():
        log_err(f"Responses file not found: {args.responses}")
        sys.exit(1)

    output = args.output or args.responses.parent / f"joined_{args.responses.stem}.jsonl"

    log_phase("Joining prompts with responses")

    with log_timer("Join"):
        # Index prompts by id
        prompts = {}
        for line in args.prompts.read_text().split("\n"):
            if not line.strip():
                continue
            entry = json.loads(line)
            prompts[entry["id"]] = entry["prompt"]
        log_info(f"Indexed {len(prompts)} prompts from {args.prompts.name}")

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
