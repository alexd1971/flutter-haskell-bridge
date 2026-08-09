"""Helpers for running external commands from build tools."""

import subprocess


def command_output(args: list[str]) -> str:
    """Run a command and return its stripped stdout as text."""
    return subprocess.check_output(args, text=True).strip()
