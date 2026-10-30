import dataclasses


@dataclasses.dataclass
class StationEntry:
    """A station's entry of the live data file; keys holds the file's keys in the file's order, others the keys the tool does not read."""
    network: str = ""
    ip: str = ""
    mac: str = ""
    rule: str = ""
    names: list = dataclasses.field(default_factory=list)
    resolution: str = ""
    destinations: list = dataclasses.field(default_factory=list)
    keys: list = dataclasses.field(default_factory=list)
    others: dict = dataclasses.field(default_factory=dict)
