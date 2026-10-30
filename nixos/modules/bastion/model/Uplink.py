import dataclasses


@dataclasses.dataclass
class Uplink:
    """A host uplink of uplinks.nix: its device, its kind (a cable's route at the start), a cable or not, the path through the VMs or not."""
    name: str = ""
    device: str = ""
    kind: str = ""
    is_cable: bool = False
    is_path: bool = False
