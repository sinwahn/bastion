import contextlib

from model.errors import FileNotDone, LibvirtNotDone
from system.errors import FileFailed, LibvirtCallFailed


class SystemFailures:
    """The system layer's failures raised again as the model's, their text carried through."""

    @contextlib.contextmanager
    def raised_as_model(self):
        try:
            yield
        except LibvirtCallFailed as failure:
            raise LibvirtNotDone(str(failure)) from failure
        except FileFailed as failure:
            raise FileNotDone(str(failure)) from failure
