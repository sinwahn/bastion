import dataclasses


@dataclasses.dataclass
class CacheBank:
    """A level 3 cache bank: its threads and its bytes per thread."""
    threads: list = dataclasses.field(default_factory=list)
    bytes_per_thread: float = 0.0
