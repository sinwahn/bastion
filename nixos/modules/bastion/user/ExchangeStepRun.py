from system.PrivilegedSteps import StepCall
from system.errors import StepFailed
from user.TerminalSteps import TerminalSteps
from user.enums import ExitCode


class ExchangeStepRun:
    """The exchange step run from the command line on the terminal as it is; its exit code the tool's."""

    def __init__(self, access):
        self.access = access

    def run(self, arguments):
        call = StepCall()
        call.step = self.access.configuration.exchange.step
        call.arguments = arguments
        try:
            TerminalSteps(self.access.privileged_steps).run(call)
        except StepFailed as failure:
            self.code = failure.code
            return
        self.code = ExitCode.kDone

    def exit_code(self):
        return self.code

    access = None
    code = ExitCode.kDone
