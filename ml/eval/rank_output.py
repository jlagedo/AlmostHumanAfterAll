#!/usr/bin/env python3
"""Rank AFM 3B output quality using Claude CLI as LLM judge.

Usage:
    uv run python eval/rank_output.py data/eval_output/output_v14_*.jsonl
    uv run python eval/rank_output.py data/eval_output/output_v14_*.jsonl --limit 10

Scores each prompt/response pair on 5 dimensions (0-3), flags failure
patterns, updates eval/version_rank.md and writes per-response details
to eval/vrank/{version}_details.md.

Re-running the same version replaces previous results.
"""

import json
import re
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

EVAL_DIR = Path(__file__).parent
RANK_FILE = EVAL_DIR / "version_rank.md"
DETAILS_DIR = EVAL_DIR / "vrank"
DIMS = ["faith", "ground", "tone", "conc", "acc"]
FLAG_CODES = "PHDECM"
FLAG_NAMES = {
    "P": "preamble",
    "H": "hallucination",
    "D": "date-parrot",
    "E": "echo",
    "C": "CTA-parrot",
    "M": "misattribution",
}

# ── Colors ───────────────────────────────────────────────────

DIM = "\033[2m"
BOLD = "\033[1m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"
CYAN = "\033[36m"
RESET = "\033[0m"

FLAG_COLORS = {
    "P": YELLOW,
    "H": RED,
    "D": BLUE,
    "E": MAGENTA,
    "C": YELLOW,
    "M": RED,
}


def log_phase(msg: str) -> None:
    print(f"\n{CYAN}{BOLD}▸ {msg}{RESET}")


def log_info(msg: str) -> None:
    print(f"  {DIM}{msg}{RESET}")


def log_ok(msg: str) -> None:
    print(f"  {GREEN}✓{RESET} {msg}")


def log_warn(msg: str) -> None:
    print(f"  {YELLOW}⚠{RESET} {msg}")


def log_err(msg: str) -> None:
    print(f"  {RED}✗{RESET} {msg}", file=sys.stderr)


def log_file(path: Path) -> None:
    print(f"  {DIM}→{RESET} {path}")


def color_score(score: float, max_score: float) -> str:
    ratio = score / max_score
    if ratio >= 0.8:
        c = GREEN
    elif ratio >= 0.5:
        c = YELLOW
    else:
        c = RED
    return f"{c}{BOLD}{score:.1f}{RESET}"


def color_flag(code: str, count: int) -> str:
    c = FLAG_COLORS.get(code, RESET)
    return f"{c}{count}{code}{RESET}"


# ── Prompt ───────────────────────────────────────────────────

SYSTEM_PROMPT = """\
You are an expert music-journalism evaluator scoring outputs from Apple's \
on-device 3B Foundation Model (AFM) for a music commentary app.

## Rubric — score each dimension 0-3

**Faithfulness (faith):** Only facts from the [Context] are used.
0 = fabricated names/facts. 1 = partial hallucination. 2 = mostly faithful, \
minor stretch. 3 = fully grounded in provided context.

**Groundedness (ground):** Every sentence maps to a specific provided fact.
0 = generic filler with no connection. 1 = mostly filler. 2 = some padding. \
3 = every claim traceable to context.

**Tone (tone):** Reads like a music journalist liner note — warm, opinionated, compact.
0 = robotic/Wikipedia. 1 = flat but functional. 2 = decent voice. \
3 = genuinely sounds like a liner note.

**Conciseness (conc):** 2-3 sentences, no meta-framing, no wasted tokens.
0 = bloated or preamble-heavy. 1 = too long or has "Here is a liner note…". \
2 = mostly tight. 3 = clean and compact.

**Accuracy (acc):** Artist names, song titles, factual claims correct vs context.
0 = wrong artist/attribution. 1 = significant error. 2 = minor imprecision. \
3 = fully correct.

## Flags — tag ALL that apply

P = preamble ("Here is…", "Liner note:", bold headers, meta-framing)
H = hallucination (fabricated names, facts, or details absent from context)
D = date-parrot (includes release dates in the liner note)
E = echo (verbatim repeats large chunks of the context)
C = CTA-parrot (echoes marketing language like "Pre-add now")
M = misattribution (wrong artist, wrong song title, confused identity)

## Calibration

Score relative to 3B-model capability. 3/3 = best a 3B model can do.
Do NOT penalise for lack of flourish a larger model might add.
DO penalise harshly for hallucination and misattribution — unacceptable at any scale.

## Output format

Respond with ONLY a JSON array. No markdown fences, no explanation.
[{{"id":1,"faith":2,"ground":1,"tone":2,"conc":1,"acc":2,"flags":["D"],"note":"short reason"}}]"""

USER_PROMPT = """\
Score each response below against its prompt context.

{responses}"""


def extract_version(path: Path) -> str:
    m = re.search(r"(v\d+)", path.stem)
    return m.group(1) if m else path.stem


def extract_genre(prompt: str) -> str:
    m = re.search(r"Genre:\s*(.+)", prompt)
    return m.group(1).strip() if m else "?"


def build_responses_block(entries: list[dict]) -> str:
    parts = []
    for i, e in enumerate(entries, 1):
        parts.append(
            f"### {i}\n"
            f"**Prompt:**\n{e['prompt']}\n\n"
            f"**Response:**\n{e['response']}"
        )
    return "\n\n".join(parts)


def call_claude(system: str, user: str) -> str:
    log_phase("Calling claude -p --model sonnet")
    total_len = len(system) + len(user)
    log_info(f"System: {len(system):,} chars · User: {len(user):,} chars (~{total_len // 4:,} tokens)")

    t0 = time.time()
    proc = subprocess.run(
        [
            "claude", "-p",
            "--model", "sonnet",
            "--output-format", "json",
            "--max-turns", "1",
            "--append-system-prompt", system,
        ],
        input=user,
        capture_output=True,
        text=True,
        timeout=600,
    )
    elapsed = time.time() - t0

    if proc.returncode != 0:
        log_err(f"Claude failed after {elapsed:.1f}s")
        log_err(proc.stderr)
        sys.exit(1)

    # Parse JSON envelope to extract response text and metadata
    try:
        envelope = json.loads(proc.stdout)
        msg = envelope[-1] if isinstance(envelope, list) else envelope

        # Extract text — try known content structures
        text = ""
        if "content" in msg:
            for block in msg["content"]:
                if isinstance(block, dict) and block.get("type") == "text":
                    text += block["text"]
                elif isinstance(block, str):
                    text += block
        elif "result" in msg:
            text = msg["result"]
        elif "text" in msg:
            text = msg["text"]

        if not text:
            # Dump structure for debugging
            log_warn("Empty text extracted from JSON envelope")
            keys = list(msg.keys()) if isinstance(msg, dict) else type(msg).__name__
            log_info(f"Envelope keys: {keys}")
            log_info(f"Raw (first 1000): {proc.stdout[:1000]}")
            sys.exit(1)

        # Log metadata
        usage = msg.get("usage", {})
        cost_raw = msg.get("cost_usd", msg.get("cost"))
        in_tok = usage.get("input_tokens", "?")
        out_tok = usage.get("output_tokens", "?")
        cost = f"${cost_raw:.4f}" if isinstance(cost_raw, (int, float)) else "?"
        log_ok(
            f"Response in {elapsed:.1f}s · "
            f"{in_tok} in / {out_tok} out · cost {cost}"
        )
    except (json.JSONDecodeError, KeyError, IndexError):
        # Fallback: treat stdout as plain text
        log_warn("Could not parse JSON envelope, falling back to raw output")
        text = proc.stdout
        log_ok(f"Response received: {len(text):,} chars in {elapsed:.1f}s")

    if proc.stderr:
        for line in proc.stderr.strip().splitlines():
            log_info(f"claude stderr: {line}")

    return text


def parse_scores(raw: str) -> list[dict]:
    log_phase("Parsing scores")
    cleaned = re.sub(r"```json\s*", "", raw)
    cleaned = re.sub(r"```\s*", "", cleaned)
    m = re.search(r"\[.*\]", cleaned, re.DOTALL)
    if not m:
        log_err("Failed to find JSON array in Claude output")
        log_err(f"First 500 chars:\n{raw[:500]}")
        sys.exit(1)
    scores = json.loads(m.group())
    log_ok(f"Parsed {len(scores)} score objects")
    return scores


def rank_entries(entries: list[dict]) -> list[dict]:
    """Score all entries in a single Claude call."""
    log_phase("Building prompt")
    block = build_responses_block(entries)
    user = USER_PROMPT.format(responses=block)
    log_ok(f"{len(entries)} responses assembled")

    raw = call_claude(SYSTEM_PROMPT, user)
    return parse_scores(raw)


# ── Aggregation ──────────────────────────────────────────────


def compute_summary(scores: list[dict]) -> dict:
    n = len(scores)
    avgs = {d: sum(s[d] for s in scores) / n for d in DIMS}
    total_avg = sum(avgs.values())

    flag_counts: dict[str, int] = {}
    for s in scores:
        for f in s.get("flags", []):
            flag_counts[f] = flag_counts.get(f, 0) + 1

    for s in scores:
        s["total"] = sum(s[d] for d in DIMS)

    ranked = sorted(scores, key=lambda s: s["total"])
    return {
        "avgs": avgs,
        "total_avg": total_avg,
        "flag_counts": flag_counts,
        "bottom": ranked[:5],
        "top": ranked[-5:][::-1],
        "n": n,
    }


# ── Formatting ───────────────────────────────────────────────


def fmt_flags_compact(fc: dict[str, int]) -> str:
    parts = [f"{fc[c]}{c}" for c in FLAG_CODES if c in fc]
    return " ".join(parts) or "—"


def fmt_flags_long(fc: dict[str, int]) -> str:
    parts = [f"{fc[c]} {FLAG_NAMES[c]}" for c in FLAG_CODES if c in fc]
    return " · ".join(parts) or "none"


def fmt_flags_colored(fc: dict[str, int]) -> str:
    parts = [color_flag(c, fc[c]) for c in FLAG_CODES if c in fc]
    return " ".join(parts) or f"{DIM}none{RESET}"


def fmt_flags_inline(flags: list[str]) -> str:
    return " ".join(flags) if flags else "—"


def fmt_table_row(version: str, today: str, s: dict) -> str:
    a = s["avgs"]
    return (
        f"| {version} | {today[5:]} "
        f"| {a['faith']:.1f} | {a['ground']:.1f} | {a['tone']:.1f} "
        f"| {a['conc']:.1f} | {a['acc']:.1f} "
        f"| **{s['total_avg']:.1f}** "
        f"| {fmt_flags_compact(s['flag_counts'])} "
        f"| {s['n']} |"
    )


def fmt_score_row(s: dict, entries: list[dict]) -> str:
    idx = s["id"] - 1
    genre = extract_genre(entries[idx]["prompt"]) if idx < len(entries) else "?"
    return f"| {s['id']} | {s['total']} | {genre} | {s.get('note', '')} |"


def fmt_section(version: str, today: str, summary: dict, entries: list[dict]) -> str:
    a = summary["avgs"]
    lines = [
        f"## {version} — {today}",
        "",
        (
            f"Faith {a['faith']:.1f} · Ground {a['ground']:.1f} · "
            f"Tone {a['tone']:.1f} · Conc {a['conc']:.1f} · "
            f"Acc {a['acc']:.1f} · **{summary['total_avg']:.1f}/15**"
        ),
        "",
        f"**Flags:** {fmt_flags_long(summary['flag_counts'])}",
        "",
        "**Bottom 5**",
        "| # | Score | Genre | Issue |",
        "|---|-------|-------|-------|",
    ]
    for s in summary["bottom"]:
        lines.append(fmt_score_row(s, entries))
    lines += [
        "",
        "**Top 5**",
        "| # | Score | Genre | Note |",
        "|---|-------|-------|------|",
    ]
    for s in summary["top"]:
        lines.append(fmt_score_row(s, entries))
    return "\n".join(lines)


# ── Details file ─────────────────────────────────────────────


def write_details(
    version: str, today: str, scores: list[dict], entries: list[dict], summary: dict
) -> Path:
    DETAILS_DIR.mkdir(parents=True, exist_ok=True)
    detail_path = DETAILS_DIR / f"{version}_details.md"

    a = summary["avgs"]
    lines = [
        f"# {version} — Detailed Ranking ({today})",
        "",
        (
            f"Faith {a['faith']:.1f} · Ground {a['ground']:.1f} · "
            f"Tone {a['tone']:.1f} · Conc {a['conc']:.1f} · "
            f"Acc {a['acc']:.1f} · **{summary['total_avg']:.1f}/15** "
            f"(n={summary['n']})"
        ),
        "",
        f"**Flags:** {fmt_flags_long(summary['flag_counts'])}",
        "",
        "---",
        "",
    ]

    sorted_scores = sorted(scores, key=lambda s: s["id"])
    for s in sorted_scores:
        idx = s["id"] - 1
        if idx >= len(entries):
            continue
        entry = entries[idx]
        genre = extract_genre(entry["prompt"])
        flags = fmt_flags_inline(s.get("flags", []))

        lines += [
            f"### #{s['id']} · {genre} · {s['total']}/15 · {flags}",
            "",
            f"Faith {s['faith']} · Ground {s['ground']} · "
            f"Tone {s['tone']} · Conc {s['conc']} · Acc {s['acc']}",
            "",
            f"> **{s.get('note', '')}**",
            "",
            "**Prompt**",
            "```",
            entry["prompt"],
            "```",
            "",
            "**Response**",
            "```",
            entry["response"],
            "```",
            "",
            "---",
            "",
        ]

    detail_path.write_text("\n".join(lines))
    return detail_path


# ── Summary file I/O ─────────────────────────────────────────

TABLE_HEADER = """\
# FM Prompt Version Rankings

| Version | Date | Faith | Ground | Tone | Conc | Acc | **Avg** | Flags | n |
|---------|------|-------|--------|------|------|-----|---------|-------|---|"""

MARKER = "<!-- /summary -->"


def update_rank_file(
    version: str, today: str, summary: dict, entries: list[dict]
) -> None:
    row = fmt_table_row(version, today, summary)
    section = fmt_section(version, today, summary, entries)

    if RANK_FILE.exists():
        content = RANK_FILE.read_text()
        if MARKER not in content:
            content = content.replace("\n\n---", f"\n{MARKER}\n\n---", 1)

        # Remove existing row for this version from summary table
        content = re.sub(
            rf"^\| {re.escape(version)} \|.*\n", "", content, flags=re.MULTILINE
        )
        # Remove existing detail section for this version
        content = re.sub(
            rf"\n---\n\n## {re.escape(version)} — .*?(?=\n---\n\n## |\Z)",
            "",
            content,
            flags=re.DOTALL,
        )

        content = content.replace(MARKER, f"{row}\n{MARKER}")
        content = content.rstrip() + "\n\n---\n\n" + section + "\n"
    else:
        RANK_FILE.parent.mkdir(parents=True, exist_ok=True)
        content = f"{TABLE_HEADER}\n{row}\n{MARKER}\n\n---\n\n{section}\n"

    RANK_FILE.write_text(content)


# ── Terminal results ─────────────────────────────────────────


def print_results(version: str, summary: dict, entries: list[dict]) -> None:
    a = summary["avgs"]

    log_phase(f"Results for {BOLD}{version}{RESET}")

    # Dimension scores
    print(
        f"  Faith {color_score(a['faith'], 3)} · "
        f"Ground {color_score(a['ground'], 3)} · "
        f"Tone {color_score(a['tone'], 3)} · "
        f"Conc {color_score(a['conc'], 3)} · "
        f"Acc {color_score(a['acc'], 3)} · "
        f"Total {color_score(summary['total_avg'], 15)}/15"
    )

    # Flags
    if summary["flag_counts"]:
        print(f"  Flags: {fmt_flags_colored(summary['flag_counts'])}")

    # Bottom 5
    print(f"\n  {RED}{BOLD}Bottom 5{RESET}")
    for s in summary["bottom"]:
        idx = s["id"] - 1
        genre = extract_genre(entries[idx]["prompt"]) if idx < len(entries) else "?"
        flags = " ".join(
            f"{FLAG_COLORS.get(f, '')}{f}{RESET}" for f in s.get("flags", [])
        )
        print(
            f"  {DIM}#{s['id']:>3}{RESET}  "
            f"{RED}{s['total']:>2}/15{RESET}  "
            f"{DIM}{genre:<14}{RESET} "
            f"{flags:>10}  "
            f"{s.get('note', '')}"
        )

    # Top 5
    print(f"\n  {GREEN}{BOLD}Top 5{RESET}")
    for s in summary["top"]:
        idx = s["id"] - 1
        genre = extract_genre(entries[idx]["prompt"]) if idx < len(entries) else "?"
        print(
            f"  {DIM}#{s['id']:>3}{RESET}  "
            f"{GREEN}{s['total']:>2}/15{RESET}  "
            f"{DIM}{genre:<14}{RESET} "
            f"{s.get('note', '')}"
        )
    print()


# ── Main ─────────────────────────────────────────────────────


def main() -> None:
    if len(sys.argv) < 2:
        print(
            f"{CYAN}Usage:{RESET} uv run python eval/rank_output.py "
            f"<output.jsonl> [--limit N]"
        )
        sys.exit(1)

    path = Path(sys.argv[1])
    if not path.exists():
        log_err(f"Not found: {path}")
        sys.exit(1)

    limit = None
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])

    version = extract_version(path)
    today = date.today().isoformat()

    log_phase(f"Loading {BOLD}{path.name}{RESET}")
    entries = [json.loads(l) for l in path.read_text().splitlines() if l.strip()]
    if limit:
        entries = entries[:limit]
        log_info(f"Limited to {limit} entries")
    log_ok(f"{len(entries)} responses loaded for {BOLD}{version}{RESET}")

    scores = rank_entries(entries)

    if len(scores) != len(entries):
        log_warn(f"Got {len(scores)} scores for {len(entries)} entries")

    log_phase("Computing summary")
    summary = compute_summary(scores)
    log_ok("Aggregation complete")

    log_phase("Writing reports")
    update_rank_file(version, today, summary, entries)
    log_file(RANK_FILE)
    detail_path = write_details(version, today, scores, entries, summary)
    log_file(detail_path)

    print_results(version, summary, entries)


if __name__ == "__main__":
    main()
