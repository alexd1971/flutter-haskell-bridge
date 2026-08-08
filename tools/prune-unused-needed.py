"""Prune unused DT_NEEDED entries from a shared library.

The script keeps dependencies that provide at least one currently undefined
dynamic symbol and removes dependencies that do not provide any of them.
It is intentionally conservative around missing candidates and system
libraries: those entries are left untouched.
"""

import argparse
import subprocess
from pathlib import Path


def read_command_output_lines(command: list[str]) -> list[str]:
    """Run a command and return stdout lines, or an empty list on failure."""
    result = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode != 0:
        return []
    return result.stdout.splitlines()


def dynamic_symbols(options: list[str], library: Path) -> set[str]:
    """Return dynamic symbols reported by nm for a shared library."""
    symbols = set()
    for line in read_command_output_lines(["nm", "-D", *options, str(library)]):
        fields = line.split()
        if not fields:
            continue
        symbol = fields[-1].split("@", 1)[0]
        if symbol:
            symbols.add(symbol)
    return symbols


def needed_libraries(library: Path) -> list[str]:
    """Return DT_NEEDED library names recorded in a shared library."""
    return read_command_output_lines(["patchelf", "--print-needed", str(library)])


def load_candidates(candidates_file: Path) -> dict[str, Path]:
    """Load DT_NEEDED resolution candidates from a TSV file.

    Each row maps a shared library basename, as it appears in DT_NEEDED, to a
    concrete file path that can be inspected for exported dynamic symbols.
    """
    candidates: dict[str, Path] = {}
    with candidates_file.open() as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            name, _, path = line.partition("\t")
            if name and path and name not in candidates:
                candidates[name] = Path(path)
    return candidates


def remove_needed(library: Path, needed: str) -> None:
    """Remove one DT_NEEDED entry from a shared library."""
    subprocess.run(
        ["patchelf", "--remove-needed", needed, str(library)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def prune_unused_needed(
    library: Path,
    candidates: dict[str, Path],
    system_libraries: set[str],
) -> None:
    """Remove dependencies that do not resolve any undefined dynamic symbol."""
    undefined_symbols = dynamic_symbols(["-u"], library)

    for needed in needed_libraries(library):
        if needed in system_libraries:
            continue

        candidate = candidates.get(needed)
        if candidate is None:
            continue

        defined_symbols = dynamic_symbols(["--defined-only"], candidate)
        if undefined_symbols.isdisjoint(defined_symbols):
            remove_needed(library, needed)


def main() -> None:
    """Parse CLI arguments and prune unused DT_NEEDED entries."""
    parser = argparse.ArgumentParser(
        description="Remove DT_NEEDED entries that do not satisfy undefined dynamic symbols.",
    )
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--candidates", required=True, type=Path)
    parser.add_argument(
        "--system-library",
        action="append",
        default=[],
        help="Library name that should never be removed.",
    )
    args = parser.parse_args()

    prune_unused_needed(
        args.library,
        load_candidates(args.candidates),
        set(args.system_library),
    )


if __name__ == "__main__":
    main()
