from user.enums import ExitCode
from user.errors import Stop


class CommandLine:
    """The command line: the first command that accepts the words given run, else the help printed."""

    def __init__(self, commands, help_text):
        self.commands = commands
        self.help_text = help_text

    def run(self, arguments):
        for command in self.commands:
            if command.accepts(arguments):
                self._run(command, arguments)
                return
        self.help_text.print_lines()
        self.code = ExitCode.kStopped

    def exit_code(self):
        return self.code

    def _run(self, command, arguments):
        try:
            command.run(arguments)
        except Stop as stop:
            print(stop)
            self.code = ExitCode.kStopped
            return
        self.code = command.exit_code()

    commands = ()
    help_text = None
    code = ExitCode.kDone
