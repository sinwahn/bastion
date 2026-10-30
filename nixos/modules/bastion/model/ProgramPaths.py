import dataclasses


@dataclasses.dataclass
class ProgramPaths:
    """The store paths of the programs the tool runs, and of bastion.nix's privileged steps by name."""
    nmcli: str = ""
    ip: str = ""
    socat: str = ""
    bridge: str = ""
    systemctl: str = ""
    privileged: dict = dataclasses.field(default_factory=dict)
