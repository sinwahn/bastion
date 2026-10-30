class Changes:
    """What this run changed since the copy was last written: the VMs defined, changed or undefined, and the live data file."""

    def __init__(self):
        self.names = set()

    def add(self, name):
        self.names.add(name)

    def any(self):
        return bool(self.names)

    def clear(self):
        self.names.clear()

    names = frozenset()
