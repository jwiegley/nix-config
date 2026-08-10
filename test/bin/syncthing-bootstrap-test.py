#!/usr/bin/env python3
"""Hermetic file-safety tests for the Syncthing bootstrap helper."""

import errno
import importlib.util
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "config" / "syncthing-bootstrap.py"
SPEC = importlib.util.spec_from_file_location("syncthing_bootstrap", SCRIPT)
assert SPEC is not None
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class SyncthingBootstrapFileSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.config = self.root / "config.xml"

    @staticmethod
    def snapshot(path):
        metadata = path.lstat()
        return (
            path.read_bytes(),
            metadata.st_dev,
            metadata.st_ino,
            stat.S_IMODE(metadata.st_mode),
        )

    def write_original(self, mode=0o640):
        self.config.write_bytes(b"original\n")
        self.config.chmod(mode)
        return self.config.lstat()

    @staticmethod
    def replacement_tree():
        return MODULE.ET.Element("configuration", {"version": "52"})

    def assert_no_temporary_files(self):
        self.assertEqual(list(self.root.glob(".config.xml.*")), [])

    def test_read_rejects_symlink_without_touching_target(self):
        target = self.root / "target.xml"
        target.write_bytes(b"target\n")
        before = self.snapshot(target)
        self.config.symlink_to(target.name)

        with self.assertRaisesRegex(MODULE.BootstrapError, "must be a regular file"):
            MODULE.read_regular_file(self.config)

        self.assertTrue(self.config.is_symlink())
        self.assertEqual(os.readlink(self.config), target.name)
        self.assertEqual(self.snapshot(target), before)
        self.assert_no_temporary_files()

    def test_read_rejects_fifo_without_opening_it(self):
        os.mkfifo(self.config, 0o600)

        with (
            mock.patch.object(MODULE.os, "open") as opened,
            self.assertRaisesRegex(MODULE.BootstrapError, "must be a regular file"),
        ):
            MODULE.read_regular_file(self.config)

        opened.assert_not_called()
        self.assertTrue(stat.S_ISFIFO(self.config.lstat().st_mode))
        self.assert_no_temporary_files()

    def test_read_rejects_an_inode_swap_and_closes_the_opened_file(self):
        self.config.write_bytes(b"validated inode\n")
        validated = self.config.lstat()
        replacement = self.root / "replacement.xml"
        replacement.write_bytes(b"swapped inode\n")
        real_open = os.open
        opened_fds = []

        def swap_and_open(path, flags):
            os.replace(replacement, self.config)
            fd = real_open(path, flags)
            opened_fds.append(fd)
            return fd

        with (
            mock.patch.object(MODULE.os, "open", side_effect=swap_and_open),
            self.assertRaisesRegex(MODULE.BootstrapError, "changed during validation"),
        ):
            MODULE.read_regular_file(self.config)

        current = self.config.lstat()
        self.assertNotEqual(
            (current.st_dev, current.st_ino),
            (validated.st_dev, validated.st_ino),
        )
        self.assertEqual(self.config.read_bytes(), b"swapped inode\n")
        self.assertEqual(len(opened_fds), 1)
        with self.assertRaises(OSError):
            os.fstat(opened_fds[0])
        self.assert_no_temporary_files()

    def test_read_does_not_follow_a_symlink_swapped_in_after_lstat(self):
        self.config.write_bytes(b"validated inode\n")
        parked = self.root / "validated.xml"
        target = self.root / "target.xml"
        target.write_bytes(b"symlink target\n")
        before = self.snapshot(target)
        real_open = os.open

        def swap_and_open(path, flags):
            self.config.rename(parked)
            self.config.symlink_to(target.name)
            self.assertNotEqual(flags & os.O_NOFOLLOW, 0)
            return real_open(path, flags)

        with (
            mock.patch.object(MODULE.os, "open", side_effect=swap_and_open),
            self.assertRaises(OSError) as raised,
        ):
            MODULE.read_regular_file(self.config)

        self.assertEqual(raised.exception.errno, errno.ELOOP)
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(parked.read_bytes(), b"validated inode\n")
        self.assertEqual(self.snapshot(target), before)

    def test_read_nonblocking_fifo_swap_is_rejected_and_closed(self):
        self.config.write_bytes(b"validated inode\n")
        parked = self.root / "validated.xml"
        fifo = self.root / "replacement.fifo"
        os.mkfifo(fifo, 0o600)
        real_open = os.open
        opened_fds = []

        def swap_and_open(path, flags):
            self.assertNotEqual(flags & os.O_NONBLOCK, 0)
            self.config.rename(parked)
            fifo.rename(self.config)
            fd = real_open(path, flags)
            opened_fds.append(fd)
            return fd

        with (
            mock.patch.object(MODULE.os, "open", side_effect=swap_and_open),
            self.assertRaisesRegex(MODULE.BootstrapError, "must remain a regular file"),
        ):
            MODULE.read_regular_file(self.config)

        self.assertTrue(stat.S_ISFIFO(self.config.lstat().st_mode))
        self.assertEqual(parked.read_bytes(), b"validated inode\n")
        self.assertEqual(len(opened_fds), 1)
        with self.assertRaises(OSError):
            os.fstat(opened_fds[0])

    def test_write_rejects_an_inode_swap_before_creating_a_temporary_file(self):
        original = self.write_original()
        replacement = self.root / "replacement.xml"
        replacement.write_bytes(b"swapped inode\n")
        os.replace(replacement, self.config)
        before = self.snapshot(self.config)

        with (
            mock.patch.object(MODULE.tempfile, "mkstemp") as mkstemp,
            self.assertRaisesRegex(MODULE.BootstrapError, "changed before replacement"),
        ):
            MODULE.atomic_write(self.config, self.replacement_tree(), original)

        mkstemp.assert_not_called()
        self.assertEqual(self.snapshot(self.config), before)
        self.assert_no_temporary_files()

    def test_write_preserves_mode_and_removes_the_temporary_file(self):
        original = self.write_original(mode=0o640)

        MODULE.atomic_write(self.config, self.replacement_tree(), original)

        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o640)
        self.assertEqual(MODULE.ET.parse(self.config).getroot().tag, "configuration")
        self.assert_no_temporary_files()

    def test_write_rechecks_identity_after_serialization(self):
        original = self.write_original()
        replacement = self.root / "replacement.xml"
        replacement.write_bytes(b"swapped during fsync\n")
        replacement.chmod(0o600)
        replacement_state = self.snapshot(replacement)
        real_replace = os.replace
        fsync_calls = 0

        def swap_on_file_fsync(_fd):
            nonlocal fsync_calls
            fsync_calls += 1
            if fsync_calls == 1:
                real_replace(replacement, self.config)

        with (
            mock.patch.object(MODULE.os, "fsync", side_effect=swap_on_file_fsync),
            mock.patch.object(MODULE.os, "replace") as replace,
            self.assertRaisesRegex(MODULE.BootstrapError, "changed before replacement"),
        ):
            MODULE.atomic_write(self.config, self.replacement_tree(), original)

        replace.assert_not_called()
        self.assertEqual(self.snapshot(self.config), replacement_state)
        self.assert_no_temporary_files()

    def test_write_orders_flush_fsync_replace_and_directory_fsync(self):
        original = self.write_original()
        events = []
        fsyncs = []
        real_fdopen = os.fdopen
        real_replace = os.replace
        test_case = self
        temporary_fd = None
        temporary_stat = None

        class RecordedOutput:
            def __init__(self, output):
                self.output = output

            def __enter__(self):
                self.output.__enter__()
                return self

            def __exit__(self, *args):
                return self.output.__exit__(*args)

            def fileno(self):
                return self.output.fileno()

            def write(self, payload):
                return self.output.write(payload)

            def flush(self):
                test_case.assertTrue(stat.S_ISREG(os.fstat(self.fileno()).st_mode))
                events.append("flush:regular")
                return self.output.flush()

        def recorded_fdopen(fd, *args, **kwargs):
            nonlocal temporary_fd, temporary_stat
            temporary_fd = fd
            temporary_stat = os.fstat(fd)
            return RecordedOutput(real_fdopen(fd, *args, **kwargs))

        def recorded_fsync(fd):
            metadata = os.fstat(fd)
            fsyncs.append((fd, metadata))
            mode = metadata.st_mode
            if stat.S_ISREG(mode):
                events.append("fsync:regular")
            elif stat.S_ISDIR(mode):
                events.append("fsync:directory")
            else:
                self.fail("fsync received neither a regular file nor a directory")

        def recorded_replace(source, target):
            events.append("replace")
            return real_replace(source, target)

        with (
            mock.patch.object(MODULE.os, "fdopen", side_effect=recorded_fdopen),
            mock.patch.object(MODULE.os, "fsync", side_effect=recorded_fsync),
            mock.patch.object(MODULE.os, "replace", side_effect=recorded_replace),
        ):
            MODULE.atomic_write(self.config, self.replacement_tree(), original)

        self.assertEqual(
            events,
            ["flush:regular", "fsync:regular", "replace", "fsync:directory"],
        )
        self.assertEqual(len(fsyncs), 2)
        self.assertEqual(fsyncs[0][0], temporary_fd)
        self.assertEqual(
            (fsyncs[0][1].st_dev, fsyncs[0][1].st_ino),
            (temporary_stat.st_dev, temporary_stat.st_ino),
        )
        parent = self.config.parent.stat()
        self.assertEqual(
            (fsyncs[1][1].st_dev, fsyncs[1][1].st_ino),
            (parent.st_dev, parent.st_ino),
        )

    def test_mode_failure_closes_and_cleans_up_without_replacing_original(self):
        original = self.write_original()
        before = self.snapshot(self.config)
        temporary_fds = []

        def fail_mode(fd, _mode):
            temporary_fds.append(fd)
            raise OSError("injected fchmod failure")

        with (
            mock.patch.object(MODULE.os, "fchmod", side_effect=fail_mode),
            self.assertRaisesRegex(OSError, "injected fchmod failure"),
        ):
            MODULE.atomic_write(self.config, self.replacement_tree(), original)

        self.assertEqual(self.snapshot(self.config), before)
        self.assertEqual(len(temporary_fds), 1)
        with self.assertRaises(OSError):
            os.fstat(temporary_fds[0])
        self.assert_no_temporary_files()

    def test_file_fsync_failure_cleans_up_without_replacing_original(self):
        original = self.write_original()
        before = self.snapshot(self.config)
        synced_fds = []

        def fail_fsync(fd):
            synced_fds.append(fd)
            raise OSError("injected file fsync failure")

        with (
            mock.patch.object(MODULE.os, "fsync", side_effect=fail_fsync),
            self.assertRaisesRegex(OSError, "injected file fsync failure"),
        ):
            MODULE.atomic_write(self.config, self.replacement_tree(), original)

        self.assertEqual(self.snapshot(self.config), before)
        self.assertEqual(len(synced_fds), 1)
        with self.assertRaises(OSError):
            os.fstat(synced_fds[0])
        self.assert_no_temporary_files()

    def test_replace_failure_cleans_up_without_changing_original(self):
        original = self.write_original()
        before = self.snapshot(self.config)

        with (
            mock.patch.object(
                MODULE.os,
                "replace",
                side_effect=OSError("injected replace failure"),
            ),
            self.assertRaisesRegex(OSError, "injected replace failure"),
        ):
            MODULE.atomic_write(self.config, self.replacement_tree(), original)

        self.assertEqual(self.snapshot(self.config), before)
        self.assert_no_temporary_files()

    def test_directory_fsync_failure_closes_the_directory_after_replacement(self):
        original = self.write_original()
        synced_fds = []

        def fail_second_fsync(fd):
            synced_fds.append(fd)
            if len(synced_fds) == 2:
                raise OSError("injected directory fsync failure")

        with (
            mock.patch.object(MODULE.os, "fsync", side_effect=fail_second_fsync),
            self.assertRaisesRegex(OSError, "injected directory fsync failure"),
        ):
            MODULE.atomic_write(self.config, self.replacement_tree(), original)

        self.assertEqual(len(synced_fds), 2)
        with self.assertRaises(OSError):
            os.fstat(synced_fds[1])
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o640)
        self.assertEqual(MODULE.ET.parse(self.config).getroot().tag, "configuration")
        self.assert_no_temporary_files()


if __name__ == "__main__":
    unittest.main()
