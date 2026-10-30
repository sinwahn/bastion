import dataclasses

from model.LiveDataFileContent import LiveDataFileContent


@dataclasses.dataclass
class RestoreResult:
    """The live data file after a restore, the stations taken from the copy and the networks added."""
    content: LiveDataFileContent = dataclasses.field(default_factory=LiveDataFileContent)
    stations: list = dataclasses.field(default_factory=list)
    networks: list = dataclasses.field(default_factory=list)
