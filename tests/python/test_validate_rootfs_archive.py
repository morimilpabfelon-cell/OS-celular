from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).resolve().parents[2] / "scripts" / "validate-rootfs-archive.py"
SPEC = importlib.util.spec_from_file_location("validate_rootfs_archive", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ArchiveMemberValidationTests(unittest.TestCase):
    def test_accepts_normal_relative_paths(self) -> None:
        self.assertIsNone(MODULE.validate_member("etc/os-release\n"))
        self.assertIsNone(MODULE.validate_member("usr/bin/pacman\n"))
        self.assertIsNone(MODULE.validate_member("./var/lib/pacman/\n"))

    def test_rejects_absolute_path(self) -> None:
        self.assertIsNotNone(MODULE.validate_member("/etc/shadow\n"))

    def test_rejects_parent_traversal(self) -> None:
        self.assertIsNotNone(MODULE.validate_member("../../etc/shadow\n"))
        self.assertIsNotNone(MODULE.validate_member("usr/../etc/passwd\n"))

    def test_rejects_empty_name(self) -> None:
        self.assertIsNotNone(MODULE.validate_member("\n"))


if __name__ == "__main__":
    unittest.main()
