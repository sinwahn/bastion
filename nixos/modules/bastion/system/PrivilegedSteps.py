import dataclasses

from system.errors import StepFailed


@dataclasses.dataclass
class StepCall:
    """A privileged step to run: its name, its arguments, what it reads on standard input when it is fed, and the line shown first."""
    step: str = ""
    arguments: list = dataclasses.field(default_factory=list)
    sent: str = ""
    note: str = ""


@dataclasses.dataclass
class StepAnswer:
    output: str = ""
    lines: list = dataclasses.field(default_factory=list)
    error: str = ""


class PrivilegedSteps:
    """bastion.nix's programs that need root, run through sudo; each run keeps its answer."""

    def __init__(self, shell, programs, log):
        self.shell = shell
        self.programs = programs
        self.log = log

    def run_attached(self, step, arguments):
        self.shell.run_attached(self._command(step, arguments))
        self._keep(StepAnswer())

    def run_attached_feeding(self, step, arguments, sent):
        self.shell.run_attached_feeding(self._command(step, arguments), sent)
        self._keep(StepAnswer())

    def run_captured(self, step, arguments):
        """The step's output and errors kept as one text."""
        self.shell.run_captured(self._command(step, arguments))
        self._keep(self._joined())

    def run_captured_feeding(self, step, arguments, sent):
        self.shell.run_captured_feeding(self._command(step, arguments), sent)
        self._keep(self._joined())

    def run_apart(self, step, arguments):
        """The step's output lines and its error text kept apart."""
        self.shell.run_captured(self._command(step, arguments))
        self._keep(self._apart())

    def last_answer(self):
        return self.answer

    def _joined(self):
        finished = self.shell.finished_run()
        answer = StepAnswer()
        answer.output = (finished.stdout + finished.stderr).strip()
        return answer

    def _apart(self):
        finished = self.shell.finished_run()
        answer = StepAnswer()
        answer.lines = finished.stdout.splitlines()
        answer.error = finished.stderr.strip()
        return answer

    def _keep(self, answer):
        self.answer = answer
        finished = self.shell.finished_run()
        if finished.returncode:
            self.log.note(f"{finished.args[1]} ended with {finished.returncode}")
            raise StepFailed(finished.returncode, answer)

    def _command(self, step, arguments):
        return ["sudo", self.programs[step], *arguments]

    shell = None
    programs = {}
    log = None
    answer = StepAnswer()
