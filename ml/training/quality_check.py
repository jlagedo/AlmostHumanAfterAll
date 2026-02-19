#!/usr/bin/env python3
"""Quality checks on joined prompt+response data before training.

Input:  joined JSONL (id, prompt, response, stop_reason)
Output: filtered JSONL (same format, bad rows dropped)
"""

import argparse
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_ok, log_info, log_file, log_duration, log_warn

import sentencepiece as spm

# Unicode noise from web-scraped Genius data
_UNICODE_JUNK = re.compile(
    "[\u00ad"       # soft hyphen
    "\u200b-\u200f"  # zero-width spaces, joiners, directional marks
    "\u2028-\u2029"  # line/paragraph separators
    "\u202a-\u202e"  # bidi embedding/override
    "\u2066-\u2069"  # bidi isolates
    "\ufeff"         # BOM / zero-width no-break space
    "]"
)


def clean_text(text: str) -> str:
    """Normalize ambiguous unicode in web-scraped content."""
    text = text.replace("\u00a0", " ")  # NBSP → space
    text = _UNICODE_JUNK.sub("", text)
    return text

TOKENIZER_PATH = Path.home() / "Developer" / "adapter_training_toolkit_v26_0_0" / "assets" / "tokenizer.model"
MAX_SEQ_LEN = 4095

# Mirrors prep_splits.py — must stay in sync
SYSTEM_PROMPT = (
    "You are a world-class music journalist who writes short, descriptive song presentations.\n"
    "1. ONLY use information from the provided sections.\n"
    "2. DO NOT fabricate or alter names, titles, genres, dates, or claims.\n"
    "3. DO NOT add any information not present in the provided sections."
)
TASK_PROMPT = "Task Overview: As a world-class music journalist, present this song to the user in 3 sentences in a descriptive writing tone."

_sp: spm.SentencePieceProcessor | None = None


def get_tokenizer() -> spm.SentencePieceProcessor:
    global _sp
    if _sp is None:
        _sp = spm.SentencePieceProcessor()
        _sp.Load(str(TOKENIZER_PATH))
    return _sp


def count_tokens(entry: dict) -> int:
    """Estimate total token count for the full training row."""
    sp = get_tokenizer()
    user_content = entry["prompt"] + "\n\n" + TASK_PROMPT
    total = (
        len(sp.Encode(SYSTEM_PROMPT))
        + len(sp.Encode(user_content))
        + len(sp.Encode(entry["response"]))
    )
    return total


REFUSAL_OPENERS = [
    "i appreciate",
    "i notice",
    "i cannot",
    "i can't",
    "i'm unable",
    "unfortunately",
    "i need to flag",
]


def check(entry: dict) -> str | None:
    """Return a rejection reason, or None if the entry passes."""
    resp = entry.get("response", "")

    # Refusal / metadata-mismatch responses
    lower = resp.lower()
    if any(lower.startswith(p) for p in REFUSAL_OPENERS):
        return "refusal"

    # Length bounds
    if len(resp) < 100:
        return "too_short"
    if len(resp) > 1500:
        return "too_long"

    # Sequence length (full training row must fit in model context)
    if count_tokens(entry) > MAX_SEQ_LEN:
        return "too_many_tokens"

    return None


def main():
    parser = argparse.ArgumentParser(
        description="Run quality checks on joined prompt+response data before training. "
                    "Filters out entries that are too short/long, exceed the model's "
                    "sequence length, or contain refusal patterns. Also normalizes "
                    "unicode artifacts from web-scraped Genius data.",
        epilog="""\
examples:
  uv run python training/quality_check.py data/synth/joined_batch_abc123.jsonl
  uv run python training/quality_check.py data/synth/joined.jsonl -o data/synth/clean.jsonl

checks applied:
  - refusal detection   (responses starting with "I appreciate", "I cannot", etc.)
  - length bounds       (response must be 100-1500 characters)
  - sequence length     (full training row must fit in 4095 tokens)
  - unicode cleanup     (strips zero-width chars, NBSP, bidi marks)

requires:
  SentencePiece tokenizer at ~/Developer/adapter_training_toolkit_v26_0_0/assets/tokenizer.model""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "input", type=Path,
        help="joined JSONL file — each line must have 'id', 'prompt', 'response', "
             "and 'stop_reason' fields (produced by join_batches.py)",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=None,
        help="output JSONL path for entries that pass all checks "
             "(default: <input_stem>_checked.jsonl in the same directory)",
    )
    args = parser.parse_args()

    if not args.input.exists():
        log_err(f"Input file not found: {args.input}")
        sys.exit(1)

    if not TOKENIZER_PATH.exists():
        log_err(f"Tokenizer not found: {TOKENIZER_PATH}")
        log_err("Download the Apple Adapter Training Toolkit and ensure the tokenizer "
                "is at the expected path.")
        sys.exit(1)

    output = args.output or args.input.parent / f"{args.input.stem}_checked.jsonl"

    log_phase("Running quality checks")

    lines = [l for l in args.input.read_text().split("\n") if l.strip()]
    total = len(lines)
    log_info(f"{total} entries to check")

    log_phase("Loading tokenizer")
    t0 = time.perf_counter()
    get_tokenizer()
    log_duration(time.perf_counter() - t0, "Tokenizer loaded")

    log_phase("Checking entries")
    t0 = time.perf_counter()
    passed = 0
    rejected = 0
    reasons: dict[str, int] = {}

    with output.open("w") as f:
        for i, line in enumerate(lines, 1):
            entry = json.loads(line)
            entry["prompt"] = clean_text(entry["prompt"])
            entry["response"] = clean_text(entry["response"])
            reason = check(entry)
            if reason:
                rejected += 1
                reasons[reason] = reasons.get(reason, 0) + 1
            else:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
                passed += 1
            if i % 100 == 0:
                log_info(f"Checked {i}/{total} entries…")

    elapsed = time.perf_counter() - t0
    log_ok(f"Passed: {passed}  Rejected: {rejected}")
    log_duration(elapsed, f"Checked {total} entries")
    log_file(output)
    if reasons:
        for r, count in sorted(reasons.items(), key=lambda x: -x[1]):
            log_info(f"{r}: {count}")


if __name__ == "__main__":
    main()
