import dataclasses

from model.Changes import Changes
from model.Configuration import Configuration


@dataclasses.dataclass
class HostAccess:
    """Everything the tool reaches on the host, built once by the entry from the configuration."""
    configuration: Configuration = dataclasses.field(default_factory=Configuration)
    log: object = None
    shell: object = None
    files: object = None
    libvirt: object = None
    changes: Changes = dataclasses.field(default_factory=Changes)
    first_starts: set = dataclasses.field(default_factory=set)
    nix_domains: object = None
    live_format: object = None
    live_data_file: object = None
    copy_folder: object = None
    shared_memory: object = None
    service_units: object = None
    windows: object = None
    privileged_steps: object = None
    glass_settings: object = None
    internet: object = None
    uplink_profiles: object = None
    switch_ports: object = None
    kernel_routes: object = None
    firewall_check: object = None
    wifi_check: object = None
    stick_files: object = None
    templates: object = None
