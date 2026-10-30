from system.PrivilegedSteps import StepCall
from system.errors import StepFailed


class LiveDataWriting:
    """The live data file written by networks-write, which saves it and has networks-apply and firewall-apply apply it."""

    def __init__(self, steps, access):
        self.steps = steps
        self.access = access

    def write(self, content):
        """networks-write's answer; StepFailed when it refused or did not apply the file."""
        call = StepCall()
        call.step = "networks-write"
        call.feeds = True
        call.sent = self.access.live_format.render(content)
        call.note = "networks-write saves networks.json and applies it (sudo may ask your password) ..."
        try:
            answer = self.steps.run(call)
        except StepFailed:
            self.access.changes.add(self.access.configuration.live_data_file)
            raise
        self.access.changes.add(self.access.configuration.live_data_file)
        return answer.output

    steps = None
    access = None
