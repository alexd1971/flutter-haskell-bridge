"""Bundle Android dynamic Haskell libraries and their runtime dependencies.

The dynamic Android build produces a root Haskell shared library whose
non-system ``DT_NEEDED`` entries must be copied into Flutter's JNI library
layout. Cabal-built libraries also rely on an executable to link the threaded
GHC RTS, but Flutter loads the library directly through Dart FFI, so this tool
adds the RTS dependency explicitly.
"""

import argparse
import shutil
from pathlib import Path

from fhb.shared_libraries import (
    add_needed,
    copy_library_with_needed,
    copy_manifest,
    file_description_contains,
    shared_libraries_under,
    shared_library_candidates,
)


def target_root_libraries(
    root_package: Path,
    *,
    file_command: Path,
    required_file_substring: str,
) -> list[Path]:
    """Find target-ABI root package shared libraries."""
    return [
        library
        for library in shared_libraries_under(root_package, (".so",))
        if file_description_contains(file_command, library, required_file_substring)
    ]


def find_threaded_rts(target_ghc: Path) -> Path:
    """Find the threaded target GHC RTS shared library."""
    for library in shared_libraries_under(target_ghc, (".so",)):
        if library.name.startswith("libHSrts-") and "_thr-ghc" in library.name:
            return library
    raise RuntimeError("Could not find the threaded target GHC RTS")


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments passed by the Nix builder."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--nm", required=True, type=Path)
    parser.add_argument("--patchelf", required=True, type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--android-abi", required=True)
    parser.add_argument("--root-package", required=True, type=Path)
    parser.add_argument("--target-ghc", required=True, type=Path)
    parser.add_argument("--store-paths", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--manifest-file")
    parser.add_argument(
        "--prune-unused-needed",
        action="store_true",
        help="Remove unused non-system DT_NEEDED entries from root libraries.",
    )
    parser.add_argument(
        "--system-library",
        action="append",
        default=[],
        help="Runtime library name that should not be copied into the bundle.",
    )
    parser.add_argument(
        "--candidate-file-substring",
        required=True,
        help="Only bundle shared libraries whose `file` output contains this substring.",
    )
    return parser.parse_args()


def main() -> None:
    """Bundle Android dynamic shared libraries into Flutter's JNI layout."""
    args = parse_args()
    output_dir = args.out / args.android_abi
    output_dir.mkdir(parents=True, exist_ok=True)

    candidates = shared_library_candidates(
        args.store_paths,
        suffixes=(".so",),
        file_command=args.file,
        required_file_substring=args.candidate_file_substring,
    )
    copied: set[str] = set()
    system_libraries = set(args.system_library)
    target_rts = find_threaded_rts(args.target_ghc)

    for root_library in target_root_libraries(
        args.root_package,
        file_command=args.file,
        required_file_substring=args.candidate_file_substring,
    ):
        copied_root = copy_library_with_needed(
            source=root_library,
            output_dir=output_dir,
            patchelf=args.patchelf,
            nm=args.nm,
            candidates=candidates,
            system_libraries=system_libraries,
            copied=copied,
            prune_needed=args.prune_unused_needed,
        )
        copy_library_with_needed(
            source=target_rts,
            output_dir=output_dir,
            patchelf=args.patchelf,
            nm=args.nm,
            candidates=candidates,
            system_libraries=system_libraries,
            copied=copied,
            prune_needed=False,
        )

        # Cabal libraries rely on the final executable to link the RTS. Dart
        # loads this library directly, so make the dependency explicit.
        add_needed(args.patchelf, copied_root, target_rts.name)

        alias = output_dir / f"lib{args.name}.so"
        if alias != copied_root:
            shutil.copyfile(copied_root, alias)
            alias.chmod(0o755)

    if args.manifest_file:
        copy_manifest(args.root_package, args.out, args.manifest_file)


if __name__ == "__main__":
    main()
