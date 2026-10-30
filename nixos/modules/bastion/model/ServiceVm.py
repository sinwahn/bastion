import dataclasses


@dataclasses.dataclass
class ServiceVm:
    """A service VM of host-networks.nix, counted in every start's sum."""
    name: str = ""
    threads: int = 0
    memory: int = 0
    unit: str = ""
    meaning: str = ""
