import dataclasses


@dataclasses.dataclass
class PinnedThreads:
    """The threads a VM's vcpus are pinned to, and the running VMs it shares a core with."""
    threads: list = dataclasses.field(default_factory=list)
    shared: list = dataclasses.field(default_factory=list)
