"""Bundle native dynamic Haskell libraries for Flutter desktop builds."""

import argparse
import shutil
from pathlib import Path

from fhb.shared_libraries import (
    copy_library_with_needed,
    copy_manifest,
    ensure_needed,
    load_store_paths,
    set_origin_rpath,
    shared_libraries_under,
    shared_library_candidates,
)


def find_root_library(root_package: Path, lib_extension: str) -> Path:
    """Find the root package shared library produced by Cabal."""
    for library in shared_libraries_under(root_package, (lib_extension,)):
        return library
    raise RuntimeError(f"Could not find a native shared library in {root_package}")


def find_native_rts(native_ghc: Path) -> Path:
    """Find the non-debug, non-threaded native GHC RTS shared library."""
    for library in shared_libraries_under(native_ghc, (".so",)):
        name = library.name
        if (
            name.startswith("libHSrts-")
            and "-ghc" in name
            and "_debug" not in name
            and "_thr" not in name
        ):
            return library
    raise RuntimeError(f"Could not find native GHC RTS in {native_ghc}")


def bundle_linux(args: argparse.Namespace, output_dir: Path, root_library: Path) -> Path:
    """Copy Linux root library, non-system dependencies, and native GHC RTS."""
    candidates = shared_library_candidates(args.store_paths, name_contains=".so")
    copied: set[str] = set()
    system_libraries = set(args.system_library)

    copied_root = copy_library_with_needed(
        source=root_library,
        output_dir=output_dir,
        patchelf=args.patchelf,
        nm=args.nm,
        candidates=candidates,
        system_libraries=system_libraries,
        copied=copied,
        prune_needed=args.prune_unused_needed,
        skip_system_source=True,
    )

    native_rts = find_native_rts(args.native_ghc)
    copy_library_with_needed(
        source=native_rts,
        output_dir=output_dir,
        patchelf=args.patchelf,
        nm=args.nm,
        candidates=candidates,
        system_libraries=system_libraries,
        copied=copied,
        prune_needed=False,
        skip_system_source=True,
    )
    ensure_needed(args.patchelf, copied_root, native_rts.name)
    return copied_root


def bundle_darwin(args: argparse.Namespace, output_dir: Path) -> None:
    """Copy closure dylibs into the output directory."""
    for store_path in load_store_paths(args.store_paths):
        for library in shared_libraries_under(store_path, (args.lib_extension,)):
            destination = output_dir / library.name
            if destination.exists():
                continue
            shutil.copyfile(library, destination)
            destination.chmod(0o755)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments passed by the Nix builder."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True, choices=["linux", "darwin"])
    parser.add_argument("--name", required=True)
    parser.add_argument("--lib-extension", required=True)
    parser.add_argument("--root-package", required=True, type=Path)
    parser.add_argument("--native-ghc", required=True, type=Path)
    parser.add_argument("--store-paths", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--manifest-file")
    parser.add_argument("--nm", type=Path)
    parser.add_argument("--patchelf", type=Path)
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
    return parser.parse_args()


def main() -> None:
    """Bundle native dynamic shared libraries into ``$out/lib``."""
    args = parse_args()
    output_dir = args.out / "lib"
    output_dir.mkdir(parents=True, exist_ok=True)

    root_library = find_root_library(args.root_package, args.lib_extension)

    if args.platform == "linux":
        if args.nm is None or args.patchelf is None:
            raise RuntimeError("Linux bundling requires --nm and --patchelf")
        bridge_library_source = bundle_linux(args, output_dir, root_library)
    else:
        bundle_darwin(args, output_dir)
        bridge_library_source = root_library

    bridge_library = output_dir / f"lib{args.name}{args.lib_extension}"
    shutil.copyfile(bridge_library_source, bridge_library)
    bridge_library.chmod(0o755)

    if args.platform == "linux":
        set_origin_rpath(args.patchelf, bridge_library)
        native_rts = find_native_rts(args.native_ghc)
        ensure_needed(args.patchelf, bridge_library, native_rts.name)

    if args.manifest_file:
        copy_manifest(args.root_package, args.out, args.manifest_file)


if __name__ == "__main__":
    main()
