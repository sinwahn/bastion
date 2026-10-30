import dataclasses


@dataclasses.dataclass(order=True, unsafe_hash=True)
class PciFunction:
    """A PCI function by its domain, bus, slot and function numbers."""
    domain: int = 0
    bus: int = 0
    slot: int = 0
    function: int = 0
