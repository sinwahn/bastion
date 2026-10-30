class YesNoOption:
    """The looking-glass window's full screen, win:fullScreen, default no (config.c 194-201), written as yes or no (common/src/option.c 101-104)."""

    def section(self):
        return "win"

    def option(self):
        return "fullScreen"

    def default(self):
        return "no"

    def offered(self):
        return ("yes", "no")

    def shown(self, value):
        """yes for 1, on, yes or true in any case and no for any other value (common/src/option.c 64-72)."""
        if value.lower() in ("1", "on", "yes", "true"):
            return "yes"
        return "no"
