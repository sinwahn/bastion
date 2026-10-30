class Refused(ValueError):
    """A value of the live data file the checks refuse; restarting networks-apply would refuse it again."""


class CopyNotWritten(Exception):
    """The copy in the copy folder is not written; the text says why."""


class VmMissing(LookupError):
    """No VM of that name in libvirt's store."""
