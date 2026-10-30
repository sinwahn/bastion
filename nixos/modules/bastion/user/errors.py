class Stop(Exception):
    """A command line step stops; the text is its STOP line or the lines that say why."""


class NotSaved(Exception):
    """A change asked on a screen is not saved; the text is the line the screen says."""
