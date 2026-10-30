from user.enums import ExitCode


class ConsoleCommand:
    """bastion console NAME: the console of any VM."""

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.kWord

    def run(self, arguments):
        self.access.windows.open_console(arguments[1])

    def exit_code(self):
        return ExitCode.kDone

    access = None
    kWord = "console"
