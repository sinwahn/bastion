from model.DefinitionCopy import DefinitionCopy
from model.errors import CopyNotWritten


class CopyPrint:
    """The copy written after a change of the command line; a failure printed."""

    def __init__(self, access):
        self.access = access

    def write(self):
        try:
            DefinitionCopy(self.access).write()
        except CopyNotWritten as failure:
            print(failure)

    access = None
