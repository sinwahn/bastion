from model.errors import FileNotDone, Refused
from user.enums import ExitCode
from user.errors import Stop


class ResolutionCommand:
    """bastion resolution NAME: the screen size NAME's station holds as its resolution, or follows when it holds none or NAME has no station."""

    # presets/attach.sh writes the answer onto the stick for the presets
    # module 96-resolution.

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.kWord

    def run(self, arguments):
        try:
            content = self.access.live_data_file.read_checked()
        except (FileNotDone, Refused) as failure:
            raise Stop(f"STOP: networks.json cannot be read ({failure}).") from failure
        name = arguments[1]
        if name in content.stations and "resolution" in content.stations[name].keys:
            print(content.stations[name].resolution)
        else:
            print("follows")

    def exit_code(self):
        return ExitCode.kDone

    access = None
    kWord = "resolution"
