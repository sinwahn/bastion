from user.BastionScreens import BastionScreens
from user.enums import ExitCode


class ScreensCommand:
    """bastion with no word: the screens; after screens that end in failure, the kept diagnostic lines."""

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return not arguments

    def run(self, arguments):
        screens = BastionScreens(self.access)
        screens.run()
        if screens.return_code:
            self.access.log.print_lines()

    def exit_code(self):
        return ExitCode.kDone

    access = None
