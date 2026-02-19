"""Shared logging helpers for ml/ scripts.

All scripts use the same Rich-based output conventions:

    Symbol  Color         Purpose
    ▸       bold cyan     Phase / section header
    ✓       green         Success
    ⚠       yellow        Warning
    ✗       red (stderr)  Error
    →       dim           Output file path
            dim           Supplementary info
"""

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
