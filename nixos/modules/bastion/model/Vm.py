import dataclasses
import xml.etree.ElementTree as ET

from model.StationEntry import StationEntry


@dataclasses.dataclass
class Vm:
    """One VM of libvirt's store, read from its definition, with its station of the live data file."""
    name: str = ""
    root: ET.Element = dataclasses.field(default_factory=lambda: ET.Element("domain"))
    active: bool = False
    vcpus: int = 0
    memory: int = 0
    disk_file: str = ""
    disk_target: str = ""
    capacity: int = 0
    allocation: int = 0
    hostdevs: list = dataclasses.field(default_factory=list)
    live_hostdevs: list = dataclasses.field(default_factory=list)
    glass: bool = False
    pins: list = dataclasses.field(default_factory=list)
    live_pins: list = dataclasses.field(default_factory=list)
    live_vsock: int = 0
    has_station: bool = False
    station: StationEntry = dataclasses.field(default_factory=StationEntry)
    template: bool = False
    nix: bool = False
