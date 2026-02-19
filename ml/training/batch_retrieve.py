#!/usr/bin/env python3
"""Poll an Anthropic batch until done, then save results.

Usage:
    uv run python training/batch_retrieve.py <batch_id>
    uv run python training/batch_retrieve.py --interval 30 <batch_id>

Output: data/synth/batch_<batch_id_short>_<date>.jsonl
    Each line: {"id": "<custom_id>", "response": "<text>", "stop_reason": "..."}
"""

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from anthropic import Anthropic, APIError
from rich.table import Table

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from lib.log import log_phase, log_info, log_ok, log_warn, log_err, log_file, console

OUTPUT_DIR = ROOT / "data" / "synth"


def print_batch_status(batch) -> None:
    counts = batch.request_counts
    total = counts.processing + counts.succeeded + counts.errored + counts.expired + counts.canceled

    table = Table(show_header=False, show_edge=False, pad_edge=False, box=None)
    table.add_column(style="dim")
    table.add_column()
    table.add_row("  Batch ID", f"[bold]{batch.id}")
    table.add_row("  Status", f"[yellow]{batch.processing_status}")
    table.add_row("  Succeeded", f"[green]{counts.succeeded}[/]/{total}")
    if counts.errored:
        table.add_row("  Errored", f"[red]{counts.errored}")
    if counts.expired:
        table.add_row("  Expired", f"[yellow]{counts.expired}")
    if counts.canceled:
        table.add_row("  Canceled", f"[dim]{counts.canceled}")
    console.print(table)


def poll(client: Anthropic, batch_id: str, interval: int) -> None:
    log_phase("Polling for completion")
    with console.status("[bold cyan]Waiting…") as status:
        while True:
            batch = client.messages.batches.retrieve(batch_id)
            counts = batch.request_counts
            total = counts.processing + counts.succeeded + counts.errored + counts.expired + counts.canceled
            status.update(
                f"[bold cyan]Polling[/] — "
                f"[green]{counts.succeeded}[/]/{total} succeeded · "
                f"{counts.processing} processing · "
                f"[red]{counts.errored}[/] errored"
            )
            if batch.processing_status == "ended":
                log_ok(
                    f"Batch ended — [green]{counts.succeeded}[/] succeeded, "
                    f"[red]{counts.errored}[/] errored"
                )
                return
            time.sleep(interval)


def retrieve(client: Anthropic, batch_id: str) -> tuple[list[dict], int]:
    log_phase("Retrieving results")
    results = []
    failed = 0
    with console.status("[bold cyan]Streaming results…"):
        for entry in client.messages.batches.results(batch_id):
            if entry.result.type == "succeeded":
                results.append({
                    "id": entry.custom_id,
                    "response": entry.result.message.content[0].text,
                    "stop_reason": entry.result.message.stop_reason,
                })
            else:
                failed += 1
                log_warn(f"[red]{entry.custom_id}[/] — {entry.result.type}")
    return results, failed


def main():
    parser = argparse.ArgumentParser(description="Poll and retrieve Anthropic batch results.")
    parser.add_argument("batch_id", help="Batch ID to retrieve")
    parser.add_argument("--interval", type=int, default=15, help="Poll interval in seconds (default: 15)")
    args = parser.parse_args()

    client = Anthropic()

    # Check current status
    log_phase("Checking batch status")
    try:
        batch = client.messages.batches.retrieve(args.batch_id)
    except APIError as e:
        log_err(f"API error: {e}")
        sys.exit(1)

    print_batch_status(batch)

    if batch.processing_status != "ended":
        poll(client, args.batch_id, args.interval)
    else:
        log_ok("Already ended, skipping poll")

    # Retrieve
    results, failed = retrieve(client, args.batch_id)

    if not results:
        log_err("No successful results to write")
        sys.exit(1)

    # Write output
    log_phase("Writing output")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    short_id = args.batch_id.split("_")[-1][:8] if "_" in args.batch_id else args.batch_id[:8]
    date = datetime.now(timezone.utc).strftime("%Y%m%d")
    out_path = OUTPUT_DIR / f"batch_{short_id}_{date}.jsonl"

    with out_path.open("w") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    log_file(out_path)

    # Summary
    log_phase("Done")
    table = Table(show_header=False, show_edge=False, pad_edge=False, box=None)
    table.add_column(style="dim")
    table.add_column()
    table.add_row("  Succeeded", f"[green]{len(results)}")
    if failed:
        table.add_row("  Failed", f"[red]{failed}")
    table.add_row("  Output", str(out_path))
    console.print(table)


if __name__ == "__main__":
    main()
