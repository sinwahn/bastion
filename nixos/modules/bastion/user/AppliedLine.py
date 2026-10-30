from model.errors import LiveDataNotApplied


class AppliedLine:
    """The line a write of the live data file shows: saved and applied, or not applied, with networks-write's answer."""

    def __init__(self, writing):
        self.writing = writing

    def write(self, content):
        try:
            self.writing.write(content)
        except LiveDataNotApplied as failure:
            self.text = "not applied: " + str(failure)
            return
        self.text = "saved and applied: " + self.writing.answer()

    def line(self):
        return self.text

    writing = None
    text = ""
