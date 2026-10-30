import dataclasses


@dataclasses.dataclass
class Template:
    """A template of bastion.nix: its word T, its domain tpl-T, its disk, its sealed mark and its Windows .iso."""
    word: str = ""
    name: str = ""
    iso: str = ""
    download: str = ""
    disk: int = 0
    memory: int = 0
    vcpus: int = 0
    win11: bool = False
    uuid: str = ""
    file: str = ""
    sealed: str = ""
