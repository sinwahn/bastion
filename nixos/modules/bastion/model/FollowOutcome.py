import dataclasses


@dataclasses.dataclass
class FollowOutcome:
    """Whether a station followed its VM's cable to another network, whether networks-write applied it, and its answer."""
    moved: bool = False
    applied: bool = False
    output: str = ""
