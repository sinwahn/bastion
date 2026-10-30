import dataclasses

from model.StationEntry import StationEntry
from model.Template import Template


@dataclasses.dataclass
class NewVm:
    """The answers of the new VM's questions."""
    name: str = ""
    template: Template = dataclasses.field(default_factory=Template)
    cores: int = 0
    fast_first: str = ""
    ram: int = 0
    disk: int = 0
    card: str = ""
    network: str = ""
    rule: str = ""
    names: list = dataclasses.field(default_factory=list)
    has_station: bool = False
    station: StationEntry = dataclasses.field(default_factory=StationEntry)
