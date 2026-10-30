from model.LiveDataFileContent import LiveDataFileContent
from model.NetworksFailure import NetworksFailure
from model.errors import Refused


class LiveDataFile:
    """The live data file of host-networks.nix (networks.json), read as the user."""

    def __init__(self, files, path, live_format):
        self.files = files
        self.path = path
        self.live_format = live_format

    def read(self):
        return self.live_format.parse(self.files.read_json(self.path))

    def read_checked(self):
        """The file's content, refused when a network's reach-each-other is not true or false."""
        values = self.files.read_json(self.path)
        for name, network in values["networks"].items():
            if not isinstance(network.get("reach-each-other"), bool):
                raise Refused(f"network {name}: reach-each-other is not true or false")
        return self.live_format.parse(values)

    def failure_of(self, error):
        """The failure a refused or unreadable file gives the screens."""
        failure = NetworksFailure()
        failure.failed = True
        failure.refused = isinstance(error, Refused)
        failure.reason = str(error)
        return failure

    def empty(self):
        content = LiveDataFileContent()
        content.keys = ["networks", "stations"]
        return content

    files = None
    path = ""
    live_format = None
