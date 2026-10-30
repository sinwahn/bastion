from model.DefinitionCopy import DefinitionCopy
from model.errors import CopyNotWritten


class CopyNotice:
    """The copy written after a change of the screens; a failure told on the screen."""

    def __init__(self, app, access):
        self.app = app
        self.access = access

    def write(self):
        try:
            DefinitionCopy(self.access).write()
        except CopyNotWritten as failure:
            self.app.notify(str(failure))

    app = None
    access = None
