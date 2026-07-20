#!/usr/bin/env python3
"""Create a deterministic JSON Lines manifest for a mounted filesystem tree."""

from __future__ import annotations

import argparse
import base64
import errno
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
from typing import Any, Iterator

_READ_CHUNK_SIZE = 1024 * 1024
_IGNORABLE_XATTR_ERRORS = {
    errno.ENODATA,
    errno.ENOTSUP,
    getattr(errno, "EOPNOTSUPP", errno.ENOTSUP),
}


def _encode_bytes(value: bytes) -> str:
    return base64.b64encode(value).decode("ascii")


def _display_path(value: bytes) -> str:
    return value.decode("utf-8", errors="surrogateescape")


def _hash_file(path: bytes) -> str:
    no_atime = getattr(os, "O_NOATIME", 0)
    if no_atime == 0:
        raise OSError(errno.ENOTSUP, "O_NOATIME is required for non-mutating inspection")

    descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | no_atime)
    digest = hashlib.sha256()
    with os.fdopen(descriptor, "rb", buffering=0) as stream:
        while True:
            chunk = stream.read(_READ_CHUNK_SIZE)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _file_type(mode: int) -> str:
    if stat.S_ISREG(mode):
        return "regular"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISCHR(mode):
        return "character_device"
    if stat.S_ISBLK(mode):
        return "block_device"
    if stat.S_ISFIFO(mode):
        return "fifo"
    if stat.S_ISSOCK(mode):
        return "socket"
    return "unknown"


def _xattrs(path: bytes) -> list[dict[str, Any]]:
    try:
        names = os.listxattr(path, follow_symlinks=False)
    except OSError as error:
        if error.errno in _IGNORABLE_XATTR_ERRORS:
            return []
        raise

    encoded: list[dict[str, Any]] = []
    for name in sorted(names):
        name_bytes = os.fsencode(name)
        item: dict[str, Any] = {"name_b64": _encode_bytes(name_bytes)}
        try:
            value = os.getxattr(path, name, follow_symlinks=False)
        except OSError as error:
            item["error_errno"] = error.errno
        else:
            item["size"] = len(value)
            item["sha256"] = hashlib.sha256(value).hexdigest()
        encoded.append(item)
    return encoded


def _walk_paths(root: bytes) -> Iterator[tuple[bytes, bytes]]:
    yield root, b"."
    root_device = os.lstat(root).st_dev

    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()

        kept_directories: list[bytes] = []
        for name in directories:
            absolute = os.path.join(current, name)
            metadata = os.lstat(absolute)
            if metadata.st_dev == root_device:
                kept_directories.append(name)
            relative = os.path.relpath(absolute, root)
            yield absolute, relative
        directories[:] = kept_directories

        for name in files:
            absolute = os.path.join(current, name)
            relative = os.path.relpath(absolute, root)
            yield absolute, relative


def _record(absolute: bytes, relative: bytes) -> dict[str, Any]:
    metadata = os.lstat(absolute)
    kind = _file_type(metadata.st_mode)
    record: dict[str, Any] = {
        "path": _display_path(relative),
        "path_b64": _encode_bytes(relative),
        "type": kind,
        "mode": format(stat.S_IMODE(metadata.st_mode), "04o"),
        "uid": metadata.st_uid,
        "gid": metadata.st_gid,
        "size": metadata.st_size,
        "inode": metadata.st_ino,
        "nlink": metadata.st_nlink,
        "blocks_512": metadata.st_blocks,
        "atime_ns": metadata.st_atime_ns,
        "mtime_ns": metadata.st_mtime_ns,
        "ctime_ns": metadata.st_ctime_ns,
        "xattrs": _xattrs(absolute),
    }

    if kind == "regular":
        record["content_sha256"] = _hash_file(absolute)
    elif kind == "symlink":
        record["target_b64"] = _encode_bytes(os.readlink(absolute))
    elif kind in {"character_device", "block_device"}:
        record["device_major"] = os.major(metadata.st_rdev)
        record["device_minor"] = os.minor(metadata.st_rdev)

    return record


def create_manifest(root: Path, output: Path) -> int:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError(f"root is not a directory: {root}")

    root_bytes = os.fsencode(root)
    output.parent.mkdir(parents=True, exist_ok=True)
    count = 0

    with output.open("w", encoding="utf-8", newline="\n") as stream:
        for absolute, relative in _walk_paths(root_bytes):
            record = _record(absolute, relative)
            stream.write(
                json.dumps(
                    record,
                    ensure_ascii=True,
                    separators=(",", ":"),
                    sort_keys=True,
                )
            )
            stream.write("\n")
            count += 1

    return count


def _parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = _parse_arguments()
    try:
        count = create_manifest(arguments.root, arguments.output)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Filesystem tree manifest created with {count} entries.")
    print(f"Manifest: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
