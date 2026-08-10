"""Helpers for bundling shared libraries into Flutter artifacts."""

import os
import shutil
import subprocess
from pathlib import Path


def command_lines(command: list[str]) -> list[str]:
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


def file_description(file_command: Path, path: Path) -> str:
    """Return the platform description reported by ``file`` for a path."""
    result = subprocess.run(
        [str(file_command), str(path)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return result.stdout


def file_description_contains(
    file_command: Path,
    library: Path,
    required_substring: str,
) -> bool:
    """Check whether ``file`` output contains a required substring."""
    return required_substring in file_description(file_command, library)


def shared_libraries_under(
    path: Path,
    suffixes: tuple[str, ...] = (),
    name_contains: str | None = None,
) -> list[Path]:
    """Find shared libraries below a path, following symlinked directories."""
    libraries: list[Path] = []
    for root, _, files in os.walk(path, followlinks=False):
        for file_name in files:
            if suffixes and file_name.endswith(suffixes):
                libraries.append(Path(root) / file_name)
            elif name_contains is not None and name_contains in file_name:
                libraries.append(Path(root) / file_name)
    return sorted(libraries)


def load_store_paths(store_paths_file: Path) -> list[Path]:
    """Read the Nix closure path list produced by ``pkgs.closureInfo``."""
    return [Path(line) for line in store_paths_file.read_text().splitlines() if line]


def shared_library_candidates(
    store_paths_file: Path,
    *,
    suffixes: tuple[str, ...] = (),
    name_contains: str | None = None,
    file_command: Path | None = None,
    required_file_substring: str | None = None,
) -> dict[str, Path]:
    """Map ``DT_NEEDED`` basenames to concrete shared library files."""
    candidates: dict[str, Path] = {}
    for store_path in load_store_paths(store_paths_file):
        for library in shared_libraries_under(
            store_path,
            suffixes=suffixes,
            name_contains=name_contains,
        ):
            if (
                file_command is not None
                and required_file_substring is not None
                and not file_description_contains(
                    file_command,
                    library,
                    required_file_substring,
                )
            ):
                continue
            candidates.setdefault(library.name, library)
    return candidates


def needed_libraries(patchelf: Path, library: Path) -> list[str]:
    """Return direct ``DT_NEEDED`` entries from a shared library."""
    return command_lines([str(patchelf), "--print-needed", str(library)])


def has_needed(patchelf: Path, library: Path, needed: str) -> bool:
    """Check whether a shared library already has a ``DT_NEEDED`` entry."""
    return needed in needed_libraries(patchelf, library)


def set_origin_rpath(patchelf: Path, library: Path) -> None:
    """Set ``$ORIGIN`` as runtime search path; ignore unsupported files."""
    subprocess.run(
        [str(patchelf), "--set-rpath", "$ORIGIN", str(library)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def dynamic_symbols(nm: Path, options: list[str], library: Path) -> set[str]:
    """Return dynamic symbols reported by ``nm`` for a shared library."""
    symbols: set[str] = set()
    for line in command_lines([str(nm), "-D", *options, str(library)]):
        fields = line.split()
        if not fields:
            continue
        symbol = fields[-1].split("@", 1)[0]
        if symbol:
            symbols.add(symbol)
    return symbols


def remove_needed(patchelf: Path, library: Path, needed: str) -> None:
    """Remove one ``DT_NEEDED`` entry from a shared library."""
    subprocess.run(
        [str(patchelf), "--remove-needed", needed, str(library)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def prune_unused_needed(
    *,
    nm: Path,
    patchelf: Path,
    library: Path,
    candidates: dict[str, Path],
    system_libraries: set[str],
) -> None:
    """Remove copied-library dependencies that resolve no undefined symbols."""
    undefined_symbols = dynamic_symbols(nm, ["-u"], library)
    for needed in needed_libraries(patchelf, library):
        if needed in system_libraries:
            continue

        candidate = candidates.get(needed)
        if candidate is None:
            continue

        defined_symbols = dynamic_symbols(nm, ["--defined-only"], candidate)
        if undefined_symbols.isdisjoint(defined_symbols):
            remove_needed(patchelf, library, needed)


def copy_library_with_needed(
    *,
    source: Path,
    output_dir: Path,
    patchelf: Path,
    nm: Path,
    candidates: dict[str, Path],
    system_libraries: set[str],
    copied: set[str],
    prune_needed: bool,
    skip_system_source: bool = False,
) -> Path:
    """Copy one library and recursively copy its non-system dependencies."""
    soname = source.name
    destination = output_dir / soname

    if skip_system_source and soname in system_libraries:
        return destination

    if soname in copied:
        return destination

    shutil.copyfile(source, destination)
    destination.chmod(0o755)
    set_origin_rpath(patchelf, destination)
    copied.add(soname)

    if prune_needed:
        prune_unused_needed(
            nm=nm,
            patchelf=patchelf,
            library=destination,
            candidates=candidates,
            system_libraries=system_libraries,
        )

    for needed in needed_libraries(patchelf, destination):
        if needed in system_libraries:
            continue

        needed_source = candidates.get(needed)
        if needed_source is None:
            continue

        copy_library_with_needed(
            source=needed_source,
            output_dir=output_dir,
            patchelf=patchelf,
            nm=nm,
            candidates=candidates,
            system_libraries=system_libraries,
            copied=copied,
            prune_needed=False,
            skip_system_source=skip_system_source,
        )

    return destination


def add_needed(patchelf: Path, library: Path, needed: str) -> None:
    """Add an explicit ``DT_NEEDED`` entry to a shared library."""
    subprocess.run(
        [str(patchelf), "--add-needed", needed, str(library)],
        check=True,
        text=True,
    )


def ensure_needed(patchelf: Path, library: Path, needed: str) -> None:
    """Add ``needed`` unless it is already present."""
    if not has_needed(patchelf, library, needed):
        add_needed(patchelf, library, needed)


def copy_manifest(root_package: Path, output_root: Path, manifest_file: str) -> None:
    """Copy the generated FFI manifest next to the library output directory."""
    manifest = root_package / manifest_file
    if not manifest.is_file():
        raise RuntimeError(f"Expected FFI manifest {manifest_file} was not produced")
    shutil.copyfile(manifest, output_root / manifest_file)
