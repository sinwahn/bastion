import logging


class Log:
    """The diagnostic lines of failures and decisions, kept apart from the tool's own lines."""

    def __init__(self, name):
        self.logger = logging.getLogger(name)

    def note(self, line):
        self.logger.debug(line)

    logger = None
