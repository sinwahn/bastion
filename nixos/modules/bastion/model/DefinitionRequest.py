import dataclasses

from system.SharedMemoryDevice import SharedMemory


@dataclasses.dataclass
class DefinitionRequest:
    """What a new Windows VM's definition holds; functions and memory only for a VM with a card, iso only for a template."""
    name: str = ""
    memory: int = 0
    vcpus: int = 0
    pins: list = dataclasses.field(default_factory=list)
    disk: str = ""
    win11: bool = False
    functions: list = dataclasses.field(default_factory=list)
    shared_memory: SharedMemory = dataclasses.field(default_factory=SharedMemory)
    uuid: str = ""
    mac: str = ""
    iso: str = ""
