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
        description="End-to-end eval pipeline: build prompts → run on-device model → "
                    "LLM judge. Each step can be skipped by supplying its output directly.",
        epilog="""\
examples:
  uv run python eval/run_eval.py v19                         # full pipeline
  uv run python eval/run_eval.py v19 -l 10                   # limit to 10 entries
  uv run python eval/run_eval.py v19 -l 10 -p 3              # 3 judge passes
  uv run python eval/run_eval.py v19 -t 0.8                  # custom temperature
  uv run python eval/run_eval.py v19 --prompts prompts.jsonl # skip build step
  uv run python eval/run_eval.py v19 --output output.jsonl   # skip build+model, judge only

pipeline steps:
  1. build_prompts.py  — assemble FM prompts from context JSONL (skip with --prompts)
  2. run_model.sh      — run prompts through on-device model   (skip with --output)
  3. judge_output.py   — score outputs with LLM judge""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "version",
        help="version tag (e.g. v19) — must match an existing instruction file at "
             "prompts/fm_instruction_<version>.json",
    )
    parser.add_argument(
        "-l", "--limit", type=int, default=None,
        help="maximum number of prompts/responses to process at each stage "
             "(default: no limit)",
    )
    parser.add_argument(
        "-p", "--passes", type=int, default=1,
        help="number of independent judge passes for variance estimation (default: 1)",
    )
    parser.add_argument(
        "-t", "--temperature", type=float, default=None,
        help="model sampling temperature forwarded to FMPromptRunner "
             "(default: model's built-in default)",
    )
    parser.add_argument(
        "--context", type=Path, default=DATA_DIR / "context_top100.jsonl",
        help="context JSONL file with MusicKit + Genius metadata "
             "(default: data/eval/context_top100.jsonl)",
    )
    parser.add_argument(
        "--prompts", type=Path, default=None,
        help="skip the build step and use this existing prompts JSONL file instead",
    )
    parser.add_argument(
        "--output", type=Path, default=None,
        help="skip build and model steps — judge this output JSONL file directly",
    )
    args = parser.parse_args()

    if args.limit is not None and args.limit < 1:
        log_err(f"--limit must be a positive integer, got {args.limit}")
        sys.exit(1)

    if args.passes < 1:
        log_err(f"--passes must be a positive integer, got {args.passes}")
        sys.exit(1)

    if args.temperature is not None and args.temperature < 0:
        log_err(f"--temperature must be non-negative, got {args.temperature}")
        sys.exit(1)

    version = args.version
    instruction = PROMPTS_DIR / f"fm_instruction_{version}.json"
    if not instruction.exists():
        log_err(f"Instruction file not found: {instruction}")
        sys.exit(1)

    if not args.output and not args.prompts and not args.context.exists():
        log_err(f"Context file not found: {args.context}")
        sys.exit(1)

    if args.prompts and not args.prompts.exists():
        log_err(f"Prompts file not found: {args.prompts}")
        sys.exit(1)

    if args.output and not args.output.exists():
        log_err(f"Output file not found: {args.output}")
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
