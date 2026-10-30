import dataclasses


@dataclasses.dataclass
class LiveDataFileContent:
    """The live data file (networks.json): its networks and its stations by name, in the file's order."""
    networks: dict = dataclasses.field(default_factory=dict)
    stations: dict = dataclasses.field(default_factory=dict)
    keys: list = dataclasses.field(default_factory=list)
    others: dict = dataclasses.field(default_factory=dict)
