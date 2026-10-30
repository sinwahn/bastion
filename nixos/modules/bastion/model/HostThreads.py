from model.CpuSet import CpuSet
from model.PinnedThreads import PinnedThreads
from model.enums import ThreadKind
from model.preferences.DenseFirst import DenseFirst
from model.preferences.FastFirst import FastFirst


class HostThreads:
    """The host's threads by kind, and the threads a VM's vcpus are pinned to when it starts."""

    def __init__(self, host):
        self.host = host

    def count(self, kind):
        return sum(1 for thread_kind in self.host.kinds.values() if thread_kind == kind.value)

    def dense_threads(self):
        return [thread for group in self.host.sibling_groups if not self._is_fast(group[0]) for thread in group]

    def kinds_text(self, threads):
        """Which kind of cores a VM got: '8 fast' or '4 dense + 2 fast'."""
        counts = {}
        for thread in threads:
            kind = self.host.kinds.get(thread, ThreadKind.kDense.value)
            counts[kind] = counts.get(kind, 0) + 1
        return " + ".join(f"{count} {kind}" for kind, count in counts.items()) or "none pinned"

    def preference_of(self, pins):
        """The VM's preference, read back from the first pin of its definition."""
        if pins and self._is_fast(pins[0]):
            return FastFirst()
        return DenseFirst()

    def pins(self, vcpus, preference, taken):
        """The threads a VM's vcpus are pinned to when it starts, whole cores at a time, and the running VMs it shares a core with."""
        # taken: {thread: [names of running VMs pinned there]}. A core is free
        # when no running VM is pinned to any of its threads.
        fast = [group for group in self.host.sibling_groups if self._is_fast(group[0])]
        dense = [group for group in self.host.sibling_groups if not self._is_fast(group[0])]
        order = preference.order(fast, dense, lambda group: not any(thread in taken for thread in group))
        pinned = PinnedThreads()
        pinned.threads = [thread for group in order for thread in group][:vcpus]
        pinned.shared = sorted({name for thread in pinned.threads for name in taken.get(thread, [])})
        return pinned

    def emulator_threads(self):
        return CpuSet.format(self.dense_threads())

    def _is_fast(self, thread):
        return self.host.kinds.get(thread) == ThreadKind.kFast.value

    host = None
