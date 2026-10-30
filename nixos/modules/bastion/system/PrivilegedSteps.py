import dataclasses

from system.errors import StepFailed


@dataclasses.dataclass
class StepCall:
    """A privileged step to run: its name, its arguments, what it reads on standard input when feeds, and the line shown first."""
    step: str = ""
    arguments: list = dataclasses.field(default_factory=list)
    feeds: bool = False
    sent: str = ""
    note: str = ""


@dataclasses.dataclass
class StepAnswer:
    output: str = ""
    lines: list = dataclasses.field(default_factory=list)
    error: str = ""


class PrivilegedSteps:
    """bastion.nix's programs that need root, run through sudo."""

    def __init__(self, shell, programs):
        self.shell = shell
        self.programs = programs

    def run_attached(self, step, arguments):
        self._finish(self.shell.run_attached(self._command(step, arguments)), StepAnswer())

    def run_attached_feeding(self, step, arguments, sent):
        self._finish(self.shell.run_attached_feeding(self._command(step, arguments), sent), StepAnswer())

    def run_captured(self, step, arguments):
        """The step's output and errors as one text."""
        return self._joined(self.shell.run_captured(self._command(step, arguments)))

    def run_captured_feeding(self, step, arguments, sent):
        return self._joined(self.shell.run_captured_feeding(self._command(step, arguments), sent))

    def run_apart(self, step, arguments):
        """The step's output lines and its error text apart."""
        finished = self.shell.run_captured(self._command(step, arguments))
        answer = StepAnswer()
        answer.lines = finished.stdout.splitlines()
        answer.error = finished.stderr.strip()
        self._finish(finished.returncode, answer)
        return answer

    def _joined(self, finished):
        answer = StepAnswer()
        answer.output = (finished.stdout + finished.stderr).strip()
        self._finish(finished.returncode, answer)
        return answer

    def _finish(self, code, answer):
        if code:
            raise StepFailed(code, answer)

    def _command(self, step, arguments):
        return ["sudo", self.programs[step], *arguments]

    shell = None
    programs = {}
