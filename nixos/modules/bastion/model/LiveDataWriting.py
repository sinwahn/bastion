from model.errors import LiveDataNotApplied
from system.PrivilegedSteps import StepCall
from system.errors import StepFailed


class LiveDataWriting:
    """The live data file written by networks-write, which saves it and has networks-apply and firewall-apply apply it."""

    def __init__(self, steps, access):
        self.steps = steps
        self.access = access

    def write(self, content):
        """networks-write run; LiveDataNotApplied when it refused or did not apply the file."""
        call = StepCall()
        call.step = "networks-write"
        call.sent = self.access.live_format.render(content)
        call.note = "networks-write saves networks.json and applies it (sudo may ask your password) ..."
        try:
            self.steps.run_feeding(call)
        except StepFailed as failure:
            self._note_change()
            raise LiveDataNotApplied(failure.answer.output) from failure
        self._note_change()

    def answer(self):
        """networks-write's answer to the last write."""
        return self.steps.last_answer().output

    def _note_change(self):
        self.access.changes.add(self.access.configuration.live_data_file)

    steps = None
    access = None
