#!/usr/bin/env python3
"""Reject archive member names that could escape the extraction root."""

from __future__ import annotations

import posixpath
import sys


def validate_member(raw_name: str) -> str | None:
    name = raw_name.rstrip("\n")
    if not name:
        return "empty archive member name"
    if "\x00" in name:
        return "NUL byte in archive member name"
    if name.startswith("/"):
        return f"absolute archive member path: {name}"

    normalized = posixpath.normpath(name)
    if normalized in {"", "."}:
        return None
    if normalized == ".." or normalized.startswith("../"):
        return f"archive member escapes extraction root: {name}"

    parts = [part for part in name.split("/") if part not in {"", "."}]
    if ".." in parts:
        return f"archive member contains parent traversal: {name}"
    return None


def main() -> int:
    seen = 0
    for line in sys.stdin:
        seen += 1
        error = validate_member(line)
        if error:
            print(f"error: {error}", file=sys.stderr)
            return 1

    if seen == 0:
        print("error: archive contains no members", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
