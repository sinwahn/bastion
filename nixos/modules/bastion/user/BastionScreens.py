from textual.app import App

from user.StatusScreen import StatusScreen


class BastionScreens(App):
    """The tool's screens: the status screen first, its title the command's name from the settings."""
    CSS = """
    .question { text-style: bold; margin: 1 0; }
    DataTable { height: 1fr; }
    OptionList { height: auto; max-height: 60%; }
    TextArea { height: 12; }
    """

    def __init__(self, access):
        super().__init__()
        self.access = access

    def on_mount(self):
        self.title = self.access.configuration.command
        self.push_screen(StatusScreen.with_keys(self.access))

    access = None
