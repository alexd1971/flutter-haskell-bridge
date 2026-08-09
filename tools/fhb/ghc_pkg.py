"""Helpers for querying the GHC package database."""

from pathlib import Path

from .commands import command_output


BOOT_PACKAGE_NAMES = ["base", "ghc-internal", "ghc-bignum", "ghc-prim", "rts"]

BOOT_PACKAGE_PATHS = [
    ("base", "stage1/libraries/base"),
    ("ghc-internal", "stage1/libraries/ghc-internal"),
    ("ghc-bignum", "stage1/libraries/ghc-bignum"),
    ("ghc-prim", "stage1/libraries/ghc-prim"),
    ("rts", "stage1/rts"),
]


def ghc_pkg_words(ghc_pkg: Path, package_name: str, field: str) -> list[str]:
    """Read a whitespace-separated field from the GHC package database."""
    output = command_output(
        [
            str(ghc_pkg),
            "field",
            package_name,
            field,
            "--simple-output",
        ]
    )
    return output.split()


def hs_library_name(ghc_pkg: Path, package_name: str) -> str:
    """Read the installed archive library name for a GHC package."""
    names = ghc_pkg_words(ghc_pkg, package_name, "hs-libraries")
    if not names:
        raise RuntimeError(f"ghc-pkg returned no hs-libraries for {package_name}")
    return names[0]
