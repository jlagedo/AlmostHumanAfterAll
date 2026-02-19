#!/usr/bin/env python3
"""End-to-end eval pipeline: build prompts → run on-device model → LLM judge.

Usage:
    uv run python eval/run_eval.py v19
    uv run python eval/run_eval.py v19 -l 10
    uv run python eval/run_eval.py v19 -l 10 -p 3
    uv run python eval/run_eval.py v19 --prompts data/eval/prompts.jsonl   # skip build
    uv run python eval/run_eval.py v19 --output data/eval/output_v19.jsonl  # skip build+model, just judge
"""

import argparse
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_info, log_ok, log_err, log_duration, fmt_duration

EVAL_DIR = ROOT / "eval"
DATA_DIR = ROOT / "data" / "eval"
PROMPTS_DIR = ROOT / "prompts"


def run(cmd: list[str], label: str) -> None:
    log_phase(label)
    log_info(f"$ {' '.join(cmd)}")
    t0 = time.perf_counter()
    result = subprocess.run(cmd)
    elapsed = time.perf_counter() - t0
    if result.returncode != 0:
        log_err(f"{label} failed (exit {result.returncode}) after {fmt_duration(elapsed)}")
        sys.exit(result.returncode)
    log_duration(elapsed, label)


def main():
    pipeline_start = time.perf_counter()
    parser = argparse.ArgumentParser(
        description="End-to-end eval: build prompts → run model → judge output."
    )
    parser.add_argument("version", help="Version tag (e.g. v19)")
    parser.add_argument("-l", "--limit", type=int, default=None,
                        help="Limit number of prompts/responses")
    parser.add_argument("-p", "--passes", type=int, default=1,
                        help="Number of judge passes (default: 1)")
    parser.add_argument("-t", "--temperature", type=float, default=None,
                        help="Model temperature (forwarded to FMPromptRunner)")
    parser.add_argument("--context", type=Path, default=DATA_DIR / "context_top100.jsonl",
                        help="Context JSONL file (default: data/eval/context_top100.jsonl)")
    parser.add_argument("--prompts", type=Path, default=None,
                        help="Skip build step, use existing prompts file")
    parser.add_argument("--output", type=Path, default=None,
                        help="Skip build+model steps, just judge this output file")
    args = parser.parse_args()

    version = args.version
    instruction = PROMPTS_DIR / f"fm_instruction_{version}.json"
    if not instruction.exists():
        log_err(f"Instruction file not found: {instruction}")
        sys.exit(1)

    # Step 1: Build prompts (unless --prompts or --output given)
    if args.output:
        prompts_file = None
        output_file = args.output
    elif args.prompts:
        prompts_file = args.prompts
    else:
        prompts_file = DATA_DIR / "prompts_top100.jsonl"
        cmd = [
            sys.executable, str(EVAL_DIR / "build_prompts.py"),
            str(args.context), "-v", version,
            "-o", str(prompts_file),
        ]
        if args.limit:
            cmd += ["-l", str(args.limit)]
        run(cmd, f"Building prompts ({version})")

    # Step 2: Run model (unless --output given)
    if not args.output:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = DATA_DIR / f"output_{version}_{timestamp}.jsonl"
        DATA_DIR.mkdir(parents=True, exist_ok=True)

        cmd = [
            str(EVAL_DIR / "run_model.sh"),
            version, str(prompts_file),
        ]
        if args.limit:
            cmd += ["-l", str(args.limit)]
        if args.temperature is not None:
            cmd += ["-t", str(args.temperature)]
        run(cmd, f"Running model ({version})")

        # run_model.sh generates its own timestamped filename, find the latest
        outputs = sorted(DATA_DIR.glob(f"output_{version}_*.jsonl"))
        if not outputs:
            log_err(f"No output file found for {version}")
            sys.exit(1)
        output_file = outputs[-1]

    # Step 3: Judge
    if not output_file.exists():
        log_err(f"Output file not found: {output_file}")
        sys.exit(1)

    cmd = [
        sys.executable, str(EVAL_DIR / "judge_output.py"),
        str(output_file),
    ]
    if args.limit:
        cmd += ["-l", str(args.limit)]
    if args.passes > 1:
        cmd += ["-p", str(args.passes)]
    run(cmd, f"Judging output ({version})")

    total = time.perf_counter() - pipeline_start
    log_phase("Done")
    log_duration(total, "Total pipeline")


if __name__ == "__main__":
    main()
