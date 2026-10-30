import types

from textual import work
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, Static

from user.BrokerScreen import BrokerScreen
from user.DevicesScreen import DevicesScreen
from user.GlassScreen import GlassScreen
from user.NetworksScreen import NetworksScreen
from user.PlainText import PlainText
from user.StatusReport import StatusReport
from user.VmsScreen import VmsScreen


class StatusScreen(Screen):
    """The status screen; with_keys makes the class the tool shows, with the broker section's key, read again and quit after these keys."""
    BINDINGS = [Binding("v", "vms", "VMs"), Binding("n", "networks", "networks"),
                Binding("d", "devices", "devices"), Binding("l", "glass", "looking-glass")]

    def __init__(self, access):
        super().__init__()
        self.access = access

    @staticmethod
    def with_keys(access):
        """The status screen the tool shows, its class made once the settings are read."""
        # textual reads a screen's keys when its class is made (textual 8.2.6
        # dom.py 565-591, 671-695), and the broker section's key is the
        # settings', so the class is made after they are read: StatusScreen's
        # keys, then that key, read again and quit, in the order of the keys
        # line.
        exchange = access.configuration.exchange
        keys = [Binding(exchange.section_key, "broker", exchange.section),
                Binding("r", "read", "read again"), Binding("q", "app.quit", "quit")]
        screen_class = types.new_class(StatusScreen.__name__, (StatusScreen,), {},
                                       lambda namespace: namespace.update(BINDINGS=keys, __module__=__name__))
        return screen_class(access)

    def compose(self):
        yield Header()
        yield Static(PlainText.of("reading the host ..."), markup=False, id="status")
        yield Footer()

    def on_mount(self):
        self.sub_title = "status"
        self.action_read()

    def action_read(self):
        self.query_one("#status", Static).update(PlainText.of("reading the host ..."))
        self._read_status()

    def action_vms(self):
        self.app.push_screen(VmsScreen(self.access))

    def action_networks(self):
        self.app.push_screen(NetworksScreen(self.access))

    def action_devices(self):
        self.app.push_screen(DevicesScreen(self.access))

    def action_glass(self):
        self.app.push_screen(GlassScreen(self.access))

    def action_broker(self):
        self.app.push_screen(BrokerScreen(self.access))

    @work(thread=True, exclusive=True)
    def _read_status(self):
        body = StatusReport(self.access).text()
        self.app.call_from_thread(self._show, body)

    def _show(self, body):
        self.query_one("#status", Static).update(PlainText.of(body))

    access = None
