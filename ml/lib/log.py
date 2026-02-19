"""Shared logging helpers for ml/ scripts.

All scripts use the same Rich-based output conventions:

    Symbol  Color         Purpose
    ▸       bold cyan     Phase / section header
    ✓       green         Success
    ⚠       yellow        Warning
    ✗       red (stderr)  Error
    →       dim           Output file path
            dim           Supplementary info
    ⏱       dim           Elapsed wall-clock time
"""

import time
from contextlib import contextmanager
from pathlib import Path

from rich.console import Console

console = Console()
err_console = Console(stderr=True)


def log_phase(msg: str) -> None:
    """Print a bold cyan phase header (e.g. ▸ Loading data)."""
    console.print(f"\n[bold cyan]▸ {msg}")


def log_info(msg: str) -> None:
    """Print a dim supplementary detail line."""
    console.print(f"  [dim]{msg}")


def log_ok(msg: str) -> None:
    """Print a green success line."""
    console.print(f"  [green]✓[/] {msg}")


def log_warn(msg: str) -> None:
    """Print a yellow warning line."""
    console.print(f"  [yellow]⚠[/] {msg}")


def log_err(msg: str) -> None:
    """Print a red error line to stderr."""
    err_console.print(f"  [red]✗[/] {msg}")


def log_file(path: Path) -> None:
    """Print a dim arrow pointing to an output file path."""
    console.print(f"  [dim]→[/] {path}")


def fmt_duration(seconds: float) -> str:
    """Format elapsed seconds into a human-readable string.

    Examples: "1.2s", "2m 34s", "1h 12m 5s"
    """
    if seconds < 60:
        return f"{seconds:.1f}s"
    m, s = divmod(int(seconds), 60)
    if m < 60:
        return f"{m}m {s}s"
    h, m = divmod(m, 60)
    return f"{h}h {m}m {s}s"


def log_duration(seconds: float, label: str = "Done") -> None:
    """Print elapsed wall-clock time for a completed phase."""
    console.print(f"  [dim]⏱ {label} in {fmt_duration(seconds)}")


@contextmanager
def log_timer(label: str = "Done"):
    """Context manager that measures wall-clock time and logs it on exit.

    Usage:
        with log_timer("Prompt building"):
            ...  # work happens here
        # prints: ⏱ Prompt building in 3.2s
    """
    t0 = time.perf_counter()
    yield
    elapsed = time.perf_counter() - t0
    log_duration(elapsed, label)
