import dataclasses

from model.AnswerPlace import AnswerPlace
from model.ExchangeWords import ExchangeWords
from model.HostShare import HostShare
from model.PickSteps import PickSteps
from model.ProgramPaths import ProgramPaths
from model.RerouteSentences import RerouteSentences


@dataclasses.dataclass
class Configuration:
    """The settings bastion.nix hands over: every name and value the tool uses that is not read from the host or libvirt."""
    command: str = ""
    entry: str = ""
    settings_file: str = ""
    uri: str = ""
    images_folder: str = ""
    retired_folder: str = ""
    virtio_iso: str = ""
    live_data_file: str = ""
    copy_folder: str = ""
    viosock_folder: str = ""
    virtio_drivers_folder: str = ""
    host_share: HostShare = dataclasses.field(default_factory=HostShare)
    pick_steps: PickSteps = dataclasses.field(default_factory=PickSteps)
    service_vms: list = dataclasses.field(default_factory=list)
    templates: list = dataclasses.field(default_factory=list)
    names_in_use: list = dataclasses.field(default_factory=list)
    name_maximum: int = 0
    refused_prefixes: list = dataclasses.field(default_factory=list)
    vsock_first: int = 0
    switch: str = ""
    host_ip: str = ""
    host_port: str = ""
    host_network_names: list = dataclasses.field(default_factory=list)
    firewall_vm: str = ""
    wifi_vm: str = ""
    broker_vm: str = ""
    wifi_uplink: str = ""
    cables: list = dataclasses.field(default_factory=list)
    uplinks: list = dataclasses.field(default_factory=list)
    reroute: RerouteSentences = dataclasses.field(default_factory=RerouteSentences)
    preferred_uplink: str = ""
    internet_target: str = ""
    internet_seconds: int = 0
    firewall_check: AnswerPlace = dataclasses.field(default_factory=AnswerPlace)
    wifi_check: AnswerPlace = dataclasses.field(default_factory=AnswerPlace)
    exchange: ExchangeWords = dataclasses.field(default_factory=ExchangeWords)
    transfers_lines: int = 0
    programs: ProgramPaths = dataclasses.field(default_factory=ProgramPaths)
