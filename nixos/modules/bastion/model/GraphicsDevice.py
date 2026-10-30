import dataclasses

from model.PciFunction import PciFunction


@dataclasses.dataclass
class GraphicsDevice:
    """A graphics device of the host: one VM's at a time when a definition gives it (passthrough), else the host's."""
    function: PciFunction = dataclasses.field(default_factory=PciFunction)
    device_class: str = ""
    driver: str = ""
    name: str = ""
    group: list = dataclasses.field(default_factory=list)
    passthrough: bool = False
    functions: list = dataclasses.field(default_factory=list)
    holders: list = dataclasses.field(default_factory=list)
