import sys


class Log:
    """The diagnostic lines of failures and decisions, kept in memory and printed only after a run that ends in failure."""

    def __init__(self):
        self.lines = []

    def note(self, line):
        self.lines.append(line)

    def print_lines(self):
        for line in self.lines:
            print(line, file=sys.stderr)

    lines = ()
