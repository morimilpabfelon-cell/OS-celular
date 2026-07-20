from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPOSITORY_ROOT / "scripts" / "manifest-ext4-tree.py"


class ManifestExt4TreeTests(unittest.TestCase):
    def run_manifest(self, root: Path, output: Path) -> list[dict[str, object]]:
        subprocess.run(
            [sys.executable, str(SCRIPT), str(root), str(output)],
            check=True,
            text=True,
            capture_output=True,
        )
        return [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]

    def test_manifest_is_stable_and_detects_content_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            base = Path(temporary_directory)
            root = base / "root"
            root.mkdir()
            directory = root / "etc"
            directory.mkdir()
            file_path = directory / "config"
            file_path.write_bytes(b"morimil\n")
            hardlink_path = directory / "config-hardlink"
            os.link(file_path, hardlink_path)
            symlink_path = root / "config-link"
            symlink_path.symlink_to("etc/config")
            os.chmod(file_path, 0o640)
            fixed_mtime_ns = 1_784_332_800_000_000_000
            fixed_atime_ns = 2_000_000_000_000_000_000
            os.utime(file_path, ns=(fixed_atime_ns, fixed_mtime_ns))
            os.utime(directory, ns=(fixed_atime_ns, fixed_mtime_ns))
            os.utime(root, ns=(fixed_atime_ns, fixed_mtime_ns))
            os.utime(
                symlink_path,
                ns=(fixed_atime_ns, fixed_mtime_ns),
                follow_symlinks=False,
            )

            try:
                os.setxattr(file_path, b"user.morimil", b"deterministic")
            except OSError:
                pass

            first_output = base / "first.jsonl"
            second_output = base / "second.jsonl"
            changed_output = base / "changed.jsonl"

            first = self.run_manifest(root, first_output)
            second = self.run_manifest(root, second_output)

            def without_atime(records: list[dict[str, object]]) -> list[dict[str, object]]:
                normalized: list[dict[str, object]] = []
                for record in records:
                    copy = dict(record)
                    copy.pop("atime_ns", None)
                    normalized.append(copy)
                return normalized

            self.assertEqual(without_atime(first), without_atime(second))

            records = {record["path"]: record for record in first}
            self.assertIn(".", records)
            self.assertIn("etc/config", records)
            self.assertIn("etc/config-hardlink", records)
            self.assertEqual(records["etc/config"]["type"], "regular")
            self.assertEqual(records["config-link"]["type"], "symlink")
            self.assertEqual(
                records["etc/config"]["inode"],
                records["etc/config-hardlink"]["inode"],
            )

            file_path.write_bytes(b"changed\n")
            changed = self.run_manifest(root, changed_output)
            self.assertNotEqual(first_output.read_bytes(), changed_output.read_bytes())
            changed_records = {record["path"]: record for record in changed}
            self.assertNotEqual(
                records["etc/config"]["content_sha256"],
                changed_records["etc/config"]["content_sha256"],
            )


if __name__ == "__main__":
    unittest.main()
