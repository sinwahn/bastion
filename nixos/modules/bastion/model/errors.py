class Refused(ValueError):
    """A value of the live data file the checks refuse; restarting networks-apply would refuse it again."""


class CopyNotWritten(Exception):
    """The copy in the copy folder is not written; the text says why."""


class VmMissing(LookupError):
    """No VM of that name in libvirt's store."""


class LibvirtNotDone(Exception):
    """A read or a change through libvirt is not done; the text is libvirt's own."""


class FileNotDone(Exception):
    """A file of the model is not read or written; the text is the reason."""


class LiveDataNotApplied(Exception):
    """networks-write refused the live data file or did not apply it; the text is its answer."""
