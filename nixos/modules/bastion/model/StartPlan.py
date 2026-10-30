import dataclasses


@dataclasses.dataclass
class StartPlan:
    """A start of a VM: the refusals, or the pins, the lines that tell which cores it gets and whom it shares them with, and its vsock number."""
    refusals: list = dataclasses.field(default_factory=list)
    pins: list = dataclasses.field(default_factory=list)
    lines: list = dataclasses.field(default_factory=list)
    vsock: int = 0
