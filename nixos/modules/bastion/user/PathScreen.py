from textual import work
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, Static

from model.errors import LibvirtNotDone
from user.PathCheck import PathCheck
from user.PlainText import PlainText


class PathScreen(Screen):
    """One VM's path check, read when the screen opens and again with r; while an answer point does not answer, a reading waits up to three times internet-wait."""
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]

    def __init__(self, access, name):
        super().__init__()
        self.access = access
        self.vm_name = name

    def compose(self):
        yield Header()
        yield Static(PlainText.of(""), markup=False, id="path")
        yield Static(PlainText.of("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = f"path check: {self.vm_name}"
        self.action_read()

    def action_read(self):
        self.query_one("#path", Static).update(PlainText.of(f"reading the path of {self.vm_name} ..."))
        self.read_path()

    @work(thread=True, exclusive=True)
    def read_path(self):
        check = PathCheck(self.access, self.vm_name)
        try:
            check.read()
            body = check.text()
        except LibvirtNotDone as error:
            body = f"libvirt cannot be read: {error}"
        self.app.call_from_thread(self.query_one("#path", Static).update, PlainText.of(body))

    access = None
    vm_name = ""
