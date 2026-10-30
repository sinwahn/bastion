from system.errors import StepFailed


class AppliedLine:
    """The line a write of the live data file shows: saved and applied, or not applied, with networks-write's answer."""

    def __init__(self, writing):
        self.writing = writing

    def write(self, content):
        try:
            return "saved and applied: " + self.writing.write(content)
        except StepFailed as failure:
            return "not applied: " + failure.answer.output

    writing = None
