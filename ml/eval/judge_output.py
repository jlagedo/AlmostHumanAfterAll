#!/usr/bin/env python3
"""Rank AFM 3B output quality using Anthropic API as LLM judge.

Usage:
    uv run python eval/judge_output.py data/eval/output_v14_*.jsonl
    uv run python eval/judge_output.py -l 10 data/eval/output_v14_*.jsonl
    uv run python eval/judge_output.py -l 5 -p 2 data/eval/output_v14_*.jsonl

Scores each prompt/response pair on 5 dimensions (0-3), flags failure
patterns, updates data/eval/version_rank.md and writes per-response details
to data/eval/vrank/{version}_details.md.

Re-running the same version replaces previous results.
"""

import argparse
import json
import re
import sys
import time
from datetime import date
from pathlib import Path

import anthropic
import pydantic
from rich.table import Table

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_info, log_ok, log_warn, log_err, log_file, log_duration, fmt_duration, console, err_console

DATA_DIR = ROOT / "data" / "eval"
RANK_FILE = DATA_DIR / "version_rank.md"
DETAILS_DIR = DATA_DIR / "vrank"
DIMS = ["faith", "ground", "tone", "conc", "acc"]
FLAG_CODES = "PHECM"
FLAG_NAMES = {
    "P": "preamble",
    "H": "hallucination",
    "E": "echo",
    "C": "CTA-parrot",
    "M": "misattribution",
}

FLAG_COLORS = {
    "P": "yellow",
    "H": "red",
    "E": "magenta",
    "C": "yellow",
    "M": "red",
}


def color_score(score: float, max_score: float) -> str:
    ratio = score / max_score
    if ratio >= 0.8:
        c = "green"
    elif ratio >= 0.5:
        c = "yellow"
    else:
        c = "red"
    return f"[{c} bold]{score:.1f}[/]"


def color_flag(code: str, count: int) -> str:
    c = FLAG_COLORS.get(code, "")
    return f"[{c}]{count}{code}[/]" if c else f"{count}{code}"


# ── Prompt ───────────────────────────────────────────────────

SYSTEM_PROMPT = """\
You are an expert music-journalism evaluator scoring outputs from Apple's \
on-device 3B Foundation Model (AFM) for a music commentary app.

## Rubric — score each dimension 0-3

**Faithfulness (faith):** Only facts from the provided sections are used.
0 = fabricated names/facts. 1 = partial fabrication. 2 = mostly faithful, \
minor stretch. 3 = fully grounded in provided sections.

**Groundedness (ground):** Every sentence maps to a specific provided fact.
0 = generic filler with no connection. 1 = mostly filler. 2 = some padding \
but core claims are grounded. 3 = every claim traceable to provided sections. \
Note: connecting language ("is a track that…", "featuring…") is structural glue, \
not filler — do not penalise it.

**Tone (tone):** Reads like a natural, descriptive song presentation.
0 = robotic/Wikipedia dump. 1 = flat but reads as coherent prose. \
2 = natural-sounding, reads well. 3 = has personality or descriptive flair.

**Conciseness (conc):** 2-3 sentences, no meta-framing, no wasted tokens.
0 = bloated or preamble-heavy. 1 = too long or has "Here is…". \
2 = mostly tight. 3 = clean and compact.

**Accuracy (acc):** Artist names, song titles, factual claims correct vs provided sections.
0 = wrong artist/attribution. 1 = significant error. 2 = minor imprecision. \
3 = fully correct.

## Flags — tag ALL that apply

P = preamble ("Here is…", "Sure,", "Liner note:", bold headers, meta-framing)
H = hallucination (the model **invented a specific fact that is objectively false** \
and does not appear anywhere in the provided sections. \
These are NOT hallucination: misattribution (flag M instead), including dates from \
the provided sections, loose paraphrases, editorial flair, connecting language, \
embellishments, vague filler, omissions, or reasonable inferences from context. \
If a date appears in any provided section and the model repeats it, that is NOT hallucination.)
E = echo (verbatim repeats large chunks of the provided sections)
C = CTA-parrot (echoes marketing language like "Pre-add now")
M = misattribution (wrong artist, wrong song title, confused identity)

## Calibration — THIS IS A 3B MODEL

You are scoring a **2-bit quantized 3B on-device model**, not GPT-4 or Claude. \
Adjust expectations accordingly:
- 3/3 = best a 3B model can reasonably produce. A clean, natural 2-3 sentence \
description with no errors IS a 3/3 output for this model.
- Connecting phrases, simple sentence structures, and functional prose are EXPECTED \
at this scale — do not penalise for lack of stylistic flourish.
- Repeating a fact from context in slightly different words is paraphrasing, not filler.
- Only flag H when the model invents a specific fact that is objectively false and \
not traceable to any provided section. When in doubt, it is NOT hallucination.

## Output format

Return a `scores` array with one object per response, using the exact field names: \
id, faith, ground, tone, conc, acc, flags, note.

The `note` field MUST cite specific evidence from the response. \
For H or M flags, quote the exact phrase that is fabricated or misattributed \
(e.g. "hallucinated 'Grammy-winning' — not in context"). \
For clean responses, note which provided sections were used."""

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


class ScoreItem(pydantic.BaseModel):
    id: int
    faith: int
    ground: int
    tone: int
    conc: int
    acc: int
    flags: list[str]
    note: str


class ScoreResponse(pydantic.BaseModel):
    scores: list[ScoreItem]


def call_judge(client: anthropic.Anthropic, user: str) -> tuple[list[dict], dict]:
    """Send the eval prompt to the API and return (parsed scores, usage dict)."""
    log_phase("Calling Anthropic API (claude-sonnet-4-5-20250929)")
    total_len = len(SYSTEM_PROMPT) + len(user)
    log_info(f"System: {len(SYSTEM_PROMPT):,} chars · User: {len(user):,} chars (~{total_len // 4:,} tokens)")

    t0 = time.perf_counter()
    with console.status("[bold cyan]Waiting for response…"):
        try:
            response = client.messages.parse(
                model="claude-sonnet-4-5-20250929",
                temperature=0,
                max_tokens=16384,
                system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
                messages=[{"role": "user", "content": [{"type": "text", "text": user, "cache_control": {"type": "ephemeral"}}]}],
                output_format=ScoreResponse,
            )
        except anthropic.APIError as e:
            elapsed = time.perf_counter() - t0
            log_err(f"API error after {fmt_duration(elapsed)}: {e}")
            sys.exit(1)
        except pydantic.ValidationError as e:
            elapsed = time.perf_counter() - t0
            log_err(f"Response parse failed after {fmt_duration(elapsed)} — output likely truncated (raise max_tokens)")
            log_err(str(e.errors()[0]["type"]))
            sys.exit(1)
    elapsed = time.perf_counter() - t0

    parsed = response.parsed_output
    if not parsed or not parsed.scores:
        log_err("Empty or unparseable response from API")
        sys.exit(1)
    if response.stop_reason == "max_tokens":
        log_warn(f"Response hit max_tokens — got {len(parsed.scores)} scores, expected more")
        sys.exit(1)

    u = response.usage
    cache_read = u.cache_read_input_tokens or 0
    cache_create = u.cache_creation_input_tokens or 0
    usage = {"input": u.input_tokens + cache_read + cache_create, "output": u.output_tokens}
    cache_parts = []
    if cache_read:
        cache_parts.append(f"[green]{cache_read:,} cached[/]")
    if cache_create:
        cache_parts.append(f"{cache_create:,} written")
    cache_str = f" · {' · '.join(cache_parts)}" if cache_parts else ""
    log_ok(
        f"Response in {elapsed:.1f}s · {len(parsed.scores)} scores · "
        f"[dim]{usage['input']:,} in / {usage['output']:,} out{cache_str}[/]"
    )
    return [s.model_dump() for s in parsed.scores], usage


def merge_passes(all_passes: list[list[dict]]) -> list[dict]:
    """Average dimension scores across passes, majority-vote flags."""
    n_passes = len(all_passes)
    n_items = len(all_passes[0])
    merged = []
    for i in range(n_items):
        item = {"id": all_passes[0][i]["id"]}
        for d in DIMS:
            item[d] = round(sum(p[i][d] for p in all_passes) / n_passes, 1)
        # flags: majority vote (present in >50% of passes)
        flag_counts: dict[str, int] = {}
        for p in all_passes:
            for f in p[i].get("flags", []):
                flag_counts[f] = flag_counts.get(f, 0) + 1
        item["flags"] = [f for f in FLAG_CODES if flag_counts.get(f, 0) > n_passes / 2]
        item["note"] = all_passes[0][i].get("note", "")
        merged.append(item)
    return merged


def compute_pass_variance(all_passes: list[list[dict]]) -> dict:
    """Compute cross-pass variance for each dimension, total, and flag splits."""
    n_passes = len(all_passes)
    n_items = len(all_passes[0])
    pass_dim_avgs: dict[str, list[float]] = {d: [] for d in DIMS}
    pass_totals: list[float] = []
    for scores in all_passes:
        n = len(scores)
        dim_avgs = {d: sum(s[d] for s in scores) / n for d in DIMS}
        for d in DIMS:
            pass_dim_avgs[d].append(dim_avgs[d])
        pass_totals.append(sum(dim_avgs.values()))

    def var(xs: list[float]) -> float:
        mean = sum(xs) / len(xs)
        return sum((x - mean) ** 2 for x in xs) / len(xs)

    # Flag splits: count items where passes disagreed on each flag
    flag_splits: dict[str, int] = {}
    for f in FLAG_CODES:
        splits = 0
        for i in range(n_items):
            votes = sum(1 for p in all_passes if f in p[i].get("flags", []))
            if 0 < votes < n_passes:
                splits += 1
        if splits:
            flag_splits[f] = splits

    # Per-item H flag votes
    h_votes: list[tuple[int, int]] = []  # (item_id, vote_count)
    for i in range(n_items):
        votes = sum(1 for p in all_passes if "H" in p[i].get("flags", []))
        if votes > 0:
            h_votes.append((all_passes[0][i]["id"], votes))
    h_per_pass = [
        sum(1 for s in p if "H" in s.get("flags", [])) for p in all_passes
    ]

    return {
        "pass_totals": pass_totals,
        "var_total": var(pass_totals),
        "dim_vars": {d: var(pass_dim_avgs[d]) for d in DIMS},
        "flag_splits": flag_splits,
        "n_items": n_items,
        "h_per_pass": h_per_pass,
        "h_votes": h_votes,
        "n_passes": n_passes,
    }


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
        s["total"] = round(sum(s[d] for d in DIMS), 1)

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
    return " ".join(parts) or "[dim]none[/]"


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
            f"### #{s['id']} · {genre} · {s['total']:g}/15 · {flags}",
            "",
            f"Faith {s['faith']:g} · Ground {s['ground']:g} · "
            f"Tone {s['tone']:g} · Conc {s['conc']:g} · Acc {s['acc']:g}",
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


def _make_table(title: str, style: str, rows: list[dict], entries: list[dict]) -> Table:
    table = Table(title=title, title_style=f"bold {style}", show_edge=False, pad_edge=False)
    table.add_column("#", style="dim", justify="right")
    table.add_column("Score", style=style, justify="right")
    table.add_column("Genre", style="dim")
    table.add_column("Flags")
    table.add_column("Note")
    for s in rows:
        idx = s["id"] - 1
        genre = extract_genre(entries[idx]["prompt"]) if idx < len(entries) else "?"
        flags = " ".join(
            f"[{FLAG_COLORS.get(f, '')}]{f}[/]" for f in s.get("flags", [])
        )
        table.add_row(str(s["id"]), f"{s['total']}/15", genre, flags, s.get("note", ""))
    return table


def print_results(version: str, summary: dict, entries: list[dict]) -> None:
    a = summary["avgs"]

    log_phase(f"Results for [bold]{version}")

    # Dimension scores
    console.print(
        f"  Faith {color_score(a['faith'], 3)} · "
        f"Ground {color_score(a['ground'], 3)} · "
        f"Tone {color_score(a['tone'], 3)} · "
        f"Conc {color_score(a['conc'], 3)} · "
        f"Acc {color_score(a['acc'], 3)} · "
        f"Total {color_score(summary['total_avg'], 15)}/15"
    )

    # Flags
    if summary["flag_counts"]:
        console.print(f"  Flags: {fmt_flags_colored(summary['flag_counts'])}")

    console.print()
    console.print(_make_table("Bottom 5", "red", summary["bottom"], entries))
    console.print()
    console.print(_make_table("Top 5", "green", summary["top"], entries))
    console.print()


# ── Main ─────────────────────────────────────────────────────


def main() -> None:
    run_start = time.perf_counter()
    parser = argparse.ArgumentParser(
        description="Score AFM 3B model outputs using an LLM judge (Claude Sonnet). "
                    "Each prompt/response pair is scored on 5 dimensions (0-3): "
                    "faithfulness, groundedness, tone, conciseness, and accuracy. "
                    "Results update data/eval/version_rank.md and write per-response "
                    "details to data/eval/vrank/<version>_details.md.",
        epilog="""\
examples:
  uv run python eval/judge_output.py data/eval/output_v14.jsonl
  uv run python eval/judge_output.py -l 10 data/eval/output_v14.jsonl
  uv run python eval/judge_output.py -l 5 -p 3 data/eval/output_v14.jsonl

note:
  Requires ANTHROPIC_API_KEY. Do NOT run inside Claude Code (it calls the
  Anthropic API and may conflict with the host process).""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-l", "--limit", type=int, default=None,
        help="maximum number of entries to evaluate (default: all entries in the file)",
    )
    parser.add_argument(
        "-p", "--passes", type=int, default=1,
        help="number of independent judge passes; when >1, dimension scores are "
             "averaged and flags are majority-voted across passes (default: 1)",
    )
    parser.add_argument(
        "file", type=Path,
        help="output JSONL file to evaluate — each line must have 'prompt' and "
             "'response' fields; the version tag is extracted from the filename "
             "(e.g. output_v14_20250601.jsonl → v14)",
    )
    args = parser.parse_args()

    if args.limit is not None and args.limit < 1:
        log_err(f"--limit must be a positive integer, got {args.limit}")
        sys.exit(1)

    if args.passes < 1:
        log_err(f"--passes must be a positive integer, got {args.passes}")
        sys.exit(1)

    path: Path = args.file
    if not path.exists():
        log_err(f"Not found: {path}")
        sys.exit(1)

    limit = args.limit
    passes = args.passes
    version = extract_version(path)
    today = date.today().isoformat()

    log_phase(f"Loading [bold]{path.name}")
    entries = [json.loads(l) for l in path.read_text().split("\n") if l.strip()]
    if limit:
        entries = entries[:limit]
        log_info(f"Limited to {limit} entries")
    log_ok(f"{len(entries)} responses loaded for [bold]{version}")

    # Build prompt once
    log_phase("Building prompt")
    block = build_responses_block(entries)
    user = USER_PROMPT.format(responses=block)
    log_ok(f"{len(entries)} responses assembled")

    # Run judge passes
    client = anthropic.Anthropic()
    all_passes = []
    total_usage = {"input": 0, "output": 0}
    for p in range(passes):
        if passes > 1:
            log_phase(f"Pass {p + 1}/{passes}")
        scores_p, usage = call_judge(client, user)
        total_usage["input"] += usage["input"]
        total_usage["output"] += usage["output"]
        if len(scores_p) != len(entries):
            log_warn(f"Got {len(scores_p)} scores for {len(entries)} entries")
        all_passes.append(scores_p)

    if passes > 1:
        variance = compute_pass_variance(all_passes)
        scores = merge_passes(all_passes)
    else:
        scores = all_passes[0]
        variance = None

    log_phase("Computing summary")
    summary = compute_summary(scores)
    log_ok("Aggregation complete")

    log_phase("Writing reports")
    update_rank_file(version, today, summary, entries)
    log_file(RANK_FILE)
    detail_path = write_details(version, today, scores, entries, summary)
    log_file(detail_path)

    print_results(version, summary, entries)

    if variance:
        log_phase(f"Variance across {passes} passes")
        for t in variance["pass_totals"]:
            log_info(f"Pass total: {t:.2f}/15")
        dv = variance["dim_vars"]
        console.print(
            f"  [dim]Var[/]  "
            f"Faith {dv['faith']:.3f} · Ground {dv['ground']:.3f} · "
            f"Tone {dv['tone']:.3f} · Conc {dv['conc']:.3f} · "
            f"Acc {dv['acc']:.3f} · "
            f"Total [bold]{variance['var_total']:.3f}"
        )
        fs = variance["flag_splits"]
        if fs:
            n = variance["n_items"]
            parts = [f"[{FLAG_COLORS.get(f, '')}]{f}[/] {c}/{n}" for f, c in fs.items()]
            console.print(f"  [dim]Flag splits[/]  {' · '.join(parts)}")
        else:
            console.print(f"  [dim]Flag splits[/]  none (all passes agreed)")

        # Hallucination detail
        h_votes = variance["h_votes"]
        n_passes_v = variance["n_passes"]
        n = variance["n_items"]
        log_phase("Hallucination flag detail")

        h_per = variance["h_per_pass"]
        console.print(f"  [dim]H per pass[/]  {' · '.join(str(c) for c in h_per)}")

        unanimous = [v for v in h_votes if v[1] == n_passes_v]
        split = [v for v in h_votes if v[1] < n_passes_v]
        clean = n - len(h_votes)

        console.print(
            f"  [green]{clean}[/] clean · "
            f"[red]{len(unanimous)}[/] unanimous H · "
            f"[yellow]{len(split)}[/] split"
        )

        if split:
            table = Table(
                title="Split H items", title_style="bold yellow",
                show_edge=False, pad_edge=False,
            )
            table.add_column("#", style="dim", justify="right")
            table.add_column("Votes", justify="center")
            table.add_column("Genre", style="dim")
            table.add_column("Note")
            for item_id, votes in sorted(split, key=lambda x: -x[1]):
                idx = item_id - 1
                genre = extract_genre(entries[idx]["prompt"]) if idx < len(entries) else "?"
                # get note from merged scores
                note = next((s.get("note", "") for s in scores if s["id"] == item_id), "")
                table.add_row(
                    str(item_id),
                    f"[yellow]{votes}[/]/{n_passes_v}",
                    genre,
                    note,
                )
            console.print()
            console.print(table)

    total_tokens = total_usage["input"] + total_usage["output"]
    console.print(
        f"  [dim]Tokens: {total_usage['input']:,} in + {total_usage['output']:,} out "
        f"= {total_tokens:,} total ({passes} pass{'es' if passes > 1 else ''})[/]"
    )
    log_duration(time.perf_counter() - run_start, "Total judging")


if __name__ == "__main__":
    main()
