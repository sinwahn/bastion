from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, Static

from model.StateReading import StateReading
from system.errors import LibvirtCallFailed
from user.HostLines import HostLines
from user.PlainText import PlainText


class DevicesScreen(Screen):
    """The host's graphics devices."""
    BINDINGS = [Binding("escape", "app.pop_screen", "back"), Binding("r", "read", "read again")]

    def __init__(self, access):
        super().__init__()
        self.access = access

    def compose(self):
        yield Header()
        yield Static(PlainText.of(""), markup=False, id="devices")
        yield Footer()

    def on_mount(self):
        self.sub_title = "devices"
        self.action_read()

    def action_read(self):
        try:
            state = StateReading(self.access).read()
            lines = HostLines(state, self.access.configuration)
            body = "\n".join(lines.device(device) for device in state.devices) or "no graphics device found"
        except LibvirtCallFailed as error:
            body = f"libvirt cannot be read: {error}"
        self.query_one("#devices", Static).update(PlainText.of(body))

    access = None
