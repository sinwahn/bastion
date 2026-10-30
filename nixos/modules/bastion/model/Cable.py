import dataclasses


@dataclasses.dataclass
class Cable:
    """A cable of host-networks.nix and the switch it is on."""
    name: str = ""
    switch: str = ""
