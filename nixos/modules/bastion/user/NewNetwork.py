import dataclasses


@dataclasses.dataclass
class NewNetwork:
    """The answers of the new network's questions: its name, empty when a question is left, its range and the VMs moving onto it."""
    name: str = ""
    ip_range: str = ""
    moving: list = dataclasses.field(default_factory=list)
