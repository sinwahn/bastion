import dataclasses


@dataclasses.dataclass
class NetworkEntry:
    """A network's entry of the live data file; keys holds the file's keys in the file's order, others the keys the tool does not read."""
    vlan_tag: int = 0
    ip_range: str = ""
    reach_each_other: bool = False
    keys: list = dataclasses.field(default_factory=list)
    others: dict = dataclasses.field(default_factory=dict)
