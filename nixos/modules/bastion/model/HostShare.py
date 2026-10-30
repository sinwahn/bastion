import dataclasses


@dataclasses.dataclass
class HostShare:
    """What always stays for the host itself: threads, RAM in GiB, disk in GiB."""
    threads: int = 0
    ram: int = 0
    disk: int = 0
