"""Link a native shared library from Haskell ``*.dyn_o`` archives.

The root package archive is linked with ``--whole-archive`` to keep exported FFI
symbols. Dependency and boot-package archives are linked normally inside a
linker group, so unused Template Haskell/build-time code is not pulled into the
runtime library.
"""

import argparse
import shutil
import subprocess
from pathlib import Path

from fhb.ghc_pkg import (
    BOOT_PACKAGE_NAMES,
    ghc_pkg_words,
    hs_library_name,
)


def dyn_archives_under(path: Path) -> list[Path]:
    """Find package-level archives built from ``*.dyn_o`` files."""
    return sorted(path.glob("**/lib/ghc-dyn-o/libHS*.a"))


def find_root_archive(root_package: Path) -> Path:
    """Find the root package archive that must keep all FFI exports."""
    archives = dyn_archives_under(root_package)
    if not archives:
        raise RuntimeError(
            f"Could not find root package dyn object archive in {root_package}"
        )
    return archives[0]


def dependency_archives(store_paths_file: Path, root_archive: Path) -> list[Path]:
    """Collect non-root package dynamic-object archives from a Nix closure."""
    archives: list[Path] = []
    seen: set[Path] = set()
    for line in store_paths_file.read_text().splitlines():
        store_path = Path(line)
        for archive in dyn_archives_under(store_path):
            if archive == root_archive or archive in seen:
                continue
            seen.add(archive)
            archives.append(archive)
    return sorted(archives)


def boot_archives(ghc_pkg: Path, dyn_archive_dir: Path) -> list[Path]:
    """Resolve GHC boot-package dynamic-object archives required for linking."""
    archives = [
        dyn_archive_dir / f"lib{hs_library_name(ghc_pkg, package_name)}.a"
        for package_name in BOOT_PACKAGE_NAMES
    ]
    missing = [archive for archive in archives if not archive.is_file()]
    if missing:
        formatted = "\n".join(str(path) for path in missing)
        raise RuntimeError(f"Missing GHC boot dyn object archives:\n{formatted}")
    return archives


def system_library_dirs(ghc_pkg: Path) -> list[str]:
    """Collect system library search directories required by GHC boot packages."""
    values: set[str] = set()
    for package_name in BOOT_PACKAGE_NAMES:
        values.update(ghc_pkg_words(ghc_pkg, package_name, "library-dirs"))
    return sorted(values)


def system_libraries(ghc_pkg: Path) -> list[str]:
    """Collect external C libraries required by GHC boot packages."""
    values: set[str] = set()
    for package_name in BOOT_PACKAGE_NAMES:
        values.update(ghc_pkg_words(ghc_pkg, package_name, "extra-libraries"))
    return sorted(values)


def link_shared_library(
    *,
    cc: Path,
    output_library: Path,
    soname: str,
    library_dirs: list[str],
    root_archive: Path,
    dependencies: list[Path],
    boot_dependencies: list[Path],
    libraries: list[str],
) -> None:
    """Invoke the C compiler as linker for the final native shared library."""
    command = [
        str(cc),
        "-shared",
        "-Wl,-Bsymbolic",
        f"-Wl,-h,{soname}",
        "-o",
        str(output_library),
        *[f"-L{library_dir}" for library_dir in library_dirs],
        "-Wl,--whole-archive",
        str(root_archive),
        "-Wl,--no-whole-archive",
        "-Wl,--start-group",
        *map(str, dependencies),
        *map(str, boot_dependencies),
        "-Wl,--end-group",
        *[f"-l{library}" for library in libraries],
    ]
    subprocess.check_call(command)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments passed by the Nix builder."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--cc", required=True, type=Path)
    parser.add_argument("--patchelf", required=True, type=Path)
    parser.add_argument("--ghc-pkg", required=True, type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--lib-extension", required=True)
    parser.add_argument("--root-package", required=True, type=Path)
    parser.add_argument("--store-paths", required=True, type=Path)
    parser.add_argument("--dyn-archive-dir", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--manifest-file")
    return parser.parse_args()


def main() -> None:
    """Link the static-Haskell native library and copy its optional manifest."""
    args = parse_args()
    if not args.dyn_archive_dir.is_dir():
        raise RuntimeError(
            f"Native GHC does not provide dyn object archives: {args.dyn_archive_dir}"
        )

    output_dir = args.out / "lib"
    output_dir.mkdir(parents=True, exist_ok=True)
    soname = f"lib{args.name}{args.lib_extension}"
    output_library = output_dir / soname

    root_archive = find_root_archive(args.root_package)
    link_shared_library(
        cc=args.cc,
        output_library=output_library,
        soname=soname,
        library_dirs=system_library_dirs(args.ghc_pkg),
        root_archive=root_archive,
        dependencies=dependency_archives(args.store_paths, root_archive),
        boot_dependencies=boot_archives(args.ghc_pkg, args.dyn_archive_dir),
        libraries=system_libraries(args.ghc_pkg),
    )

    output_library.chmod(0o755)
    subprocess.call(
        [str(args.patchelf), "--set-rpath", "$ORIGIN", str(output_library)],
        stderr=subprocess.DEVNULL,
    )

    if args.manifest_file:
        manifest = args.root_package / args.manifest_file
        if not manifest.is_file():
            raise RuntimeError(
                f"Expected FFI manifest {args.manifest_file} was not produced"
            )
        shutil.copyfile(manifest, args.out / args.manifest_file)


if __name__ == "__main__":
    main()
