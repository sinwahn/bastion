import dataclasses


@dataclasses.dataclass
class Host:
    """The host's threads, RAM in MiB, sibling groups (its cores), the kind of each thread and free disk in bytes, read live."""
    threads: int = 0
    ram: int = 0
    sibling_groups: list = dataclasses.field(default_factory=list)
    kinds: dict = dataclasses.field(default_factory=dict)
    threads_per_core: int = 1
    free: int = 0
