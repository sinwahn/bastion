import dataclasses


@dataclasses.dataclass
class PickSteps:
    """The steps of the pick lists: RAM in GiB, a disk in GiB."""
    ram: int = 0
    disk: int = 0
