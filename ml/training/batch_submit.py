#!/usr/bin/env python3
"""Submit a prompts JSONL file to Anthropic's Message Batches API.

Usage:
    uv run python training/batch_submit.py \\
        --prompts data/eval_output/prompts_top100.jsonl \\
        --instruction prompts/fm_instruction_v17.json

    uv run python training/batch_submit.py \\
        --prompts data/eval_output/prompts_top100.jsonl \\
        --system "You are a world-class music journalist..."

Appends batch metadata to batches.jsonl in the working directory.
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from anthropic import Anthropic, APIError
from rich.console import Console
from rich.table import Table

# MODEL = "claude-sonnet-4-5-20250929"
MODEL = "claude-haiku-4-5-20251001"
MAX_TOKENS = 512

console = Console()
err_console = Console(stderr=True)


def log_phase(msg: str) -> None:
    console.print(f"\n[bold cyan]▸ {msg}")


def log_info(msg: str) -> None:
    console.print(f"  [dim]{msg}")


def log_ok(msg: str) -> None:
    console.print(f"  [green]✓[/] {msg}")


def log_err(msg: str) -> None:
    err_console.print(f"  [red]✗[/] {msg}")


def log_file(path: Path) -> None:
    console.print(f"  [dim]→[/] {path}")


def load_prompts(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().split("\n") if line.strip()]


def build_requests(prompts: list[dict], system: str) -> list[dict]:
    return [
        {
            "custom_id": p["id"],
            "params": {
                "model": MODEL,
                "max_tokens": MAX_TOKENS,
                "system": system,
                "messages": [{"role": "user", "content": p["prompt"]}],
            },
        }
        for p in prompts
    ]


def main():
    parser = argparse.ArgumentParser(description="Submit prompts to Anthropic Batch API.")
    parser.add_argument("--prompts", type=Path, required=True, help="JSONL file with id + prompt fields")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--system", type=str, help="System prompt string")
    group.add_argument("--instruction", type=Path, help="Instruction JSON file (uses 'instructions' field)")
    args = parser.parse_args()

    # Load system prompt
    log_phase("Loading system prompt")
    if args.instruction:
        if not args.instruction.exists():
            log_err(f"Not found: {args.instruction}")
            sys.exit(1)
        instruction = json.loads(args.instruction.read_text())
        system = instruction["instructions"]
        log_ok(f"From [bold]{args.instruction.name}[/] ({len(system):,} chars)")
    else:
        system = args.system
        log_ok(f"Inline string ({len(system):,} chars)")

    # Load prompts
    log_phase("Loading prompts")
    if not args.prompts.exists():
        log_err(f"Not found: {args.prompts}")
        sys.exit(1)
    prompts = load_prompts(args.prompts)
    log_ok(f"{len(prompts)} prompts from [bold]{args.prompts.name}")

    # Build requests
    log_phase("Building batch requests")
    requests = build_requests(prompts, system)
    log_ok(f"{len(requests)} requests · model={MODEL} · max_tokens={MAX_TOKENS}")

    # Submit
    log_phase("Submitting to Anthropic Batch API")
    client = Anthropic()
    try:
        with console.status("[bold cyan]Creating batch…"):
            batch = client.messages.batches.create(requests=requests)
    except APIError as e:
        log_err(f"API error: {e}")
        sys.exit(1)

    now = datetime.now(timezone.utc)
    log_ok(f"Batch created")

    # Summary table
    table = Table(show_header=False, show_edge=False, pad_edge=False, box=None)
    table.add_column(style="dim")
    table.add_column()
    table.add_row("  Batch ID", f"[bold]{batch.id}")
    table.add_row("  Status", f"[yellow]{batch.processing_status}")
    table.add_row("  Requests", str(len(requests)))
    table.add_row("  Model", MODEL)
    table.add_row("  Submitted", now.strftime("%Y-%m-%d %H:%M:%S UTC"))
    console.print(table)

    # Log to file
    log_phase("Writing log")
    log_entry = {
        "batch_id": batch.id,
        "status": batch.processing_status,
        "model": MODEL,
        "max_tokens": MAX_TOKENS,
        "requests": len(requests),
        "prompts_file": str(args.prompts),
        "submitted_at": now.isoformat(),
    }
    log_path = Path("batches.jsonl")
    with log_path.open("a") as f:
        f.write(json.dumps(log_entry) + "\n")
    log_file(log_path)


if __name__ == "__main__":
    main()
