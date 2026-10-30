class LibvirtCallFailed(Exception):
    """A call into libvirt failed; the text is libvirt's own."""


class ShellCommandFailed(Exception):
    """A program could not run or did not end in time; the text is the reason."""


class FileFailed(Exception):
    """A file could not be read or written; the text is the reason."""


class StepFailed(Exception):
    """A privileged step ended with a code other than 0."""

    def __init__(self, code, answer):
        super().__init__(code)
        self.code = code
        self.answer = answer

    code = 0
    answer = None
