from user.errors import Stop


class TemplateArgument:
    """The template the command line's T names."""

    def __init__(self, access):
        self.access = access

    def template(self, arguments):
        """The template of the word after the command's word; Stop when no template has that word."""
        templates = self.access.templates
        if not templates.has(arguments[1]):
            raise Stop(f"STOP: write {templates.words()} after {self.access.configuration.command} {arguments[0]}.")
        return templates.template(arguments[1])

    access = None
