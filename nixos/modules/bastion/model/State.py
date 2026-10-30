import dataclasses

from model.Host import Host
from model.LiveDataFileContent import LiveDataFileContent
from model.NetworksFailure import NetworksFailure


@dataclasses.dataclass
class State:
    """What the screens show, read fresh from the host, libvirt and the live data file."""
    libvirt: object = None
    host: Host = dataclasses.field(default_factory=Host)
    content: LiveDataFileContent = dataclasses.field(default_factory=LiveDataFileContent)
    failure: NetworksFailure = dataclasses.field(default_factory=NetworksFailure)
    vms: list = dataclasses.field(default_factory=list)
    devices: list = dataclasses.field(default_factory=list)
