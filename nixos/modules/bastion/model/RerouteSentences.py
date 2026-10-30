import dataclasses


@dataclasses.dataclass
class RerouteSentences:
    """The sentences of a cable's route (host-networks.nix), with {cable} and {firewall} in them."""
    through: str = ""
    direct: str = ""
