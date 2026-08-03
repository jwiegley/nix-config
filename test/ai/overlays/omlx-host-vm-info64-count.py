#!/usr/bin/env python3
"""Exercise current and forward-compatible Mach host-info count handling."""

from unittest.mock import patch

from omlx.utils import psutil_compat


_PAGE_SIZE = 4096
_EXPECTED_STATS = {
    "free": 10 * _PAGE_SIZE,
    "active": 20 * _PAGE_SIZE,
    "inactive": 30 * _PAGE_SIZE,
    "wired": 40 * _PAGE_SIZE,
    "speculative": 50 * _PAGE_SIZE,
    "compressed": 60 * _PAGE_SIZE,
}


def _fill_stats(stats):
    stats[0] = 10
    stats[1] = 20
    stats[2] = 30
    stats[3] = 40
    stats[psutil_compat._VM_SPECULATIVE_INDEX] = 50
    stats[psutil_compat._VM_COMPRESSOR_INDEX] = 60


def _run(fake_libc):
    with (
        patch.object(psutil_compat, "_libc", fake_libc),
        patch.object(psutil_compat, "_MACH_HOST", 123),
        patch.object(psutil_compat, "_VM_PAGE_SIZE", _PAGE_SIZE),
    ):
        return psutil_compat.get_macos_vm_stats()


class CurrentCountLibc:
    def __init__(self):
        self.calls = []

    def host_statistics64(self, host, flavor, stats, count):
        assert host == 123
        assert flavor == psutil_compat._HOST_VM_INFO64
        self.calls.append(count._obj.value)
        assert len(stats) == psutil_compat._HOST_INFO64_MAX_COUNT
        _fill_stats(stats)
        count._obj.value = psutil_compat._HOST_VM_INFO64_COUNT
        return 0


current = CurrentCountLibc()
assert _run(current) == _EXPECTED_STATS
assert current.calls == [62]


class FutureCountLibc:
    def __init__(self):
        self.calls = []

    def host_statistics64(self, host, flavor, stats, count):
        assert host == 123
        assert flavor == psutil_compat._HOST_VM_INFO64
        self.calls.append(count._obj.value)
        assert len(stats) == psutil_compat._HOST_INFO64_MAX_COUNT
        if len(self.calls) == 1:
            count._obj.value = 104
            return psutil_compat._MIG_ARRAY_TOO_LARGE
        _fill_stats(stats)
        count._obj.value = 104
        return 0


future = FutureCountLibc()
assert _run(future) == _EXPECTED_STATS
assert future.calls == [62, 104]


class InvalidRequiredCountLibc:
    def __init__(self, required_count):
        self.required_count = required_count
        self.calls = []

    def host_statistics64(self, host, flavor, stats, count):
        self.calls.append(count._obj.value)
        count._obj.value = self.required_count
        return psutil_compat._MIG_ARRAY_TOO_LARGE


for invalid_count in (
    0,
    psutil_compat._HOST_VM_INFO64_COUNT,
    psutil_compat._HOST_INFO64_MAX_COUNT + 1,
):
    invalid = InvalidRequiredCountLibc(invalid_count)
    assert _run(invalid) is None
    assert invalid.calls == [62]


class FailedRetryLibc:
    def __init__(self):
        self.calls = []

    def host_statistics64(self, host, flavor, stats, count):
        self.calls.append(count._obj.value)
        count._obj.value = 104
        return psutil_compat._MIG_ARRAY_TOO_LARGE


failed_retry = FailedRetryLibc()
assert _run(failed_retry) is None
assert failed_retry.calls == [62, 104]
