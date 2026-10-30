from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, Static

from user.PlainText import PlainText


class TextScreen(Screen):
    """Text to read; Enter goes on, Escape goes back."""
    BINDINGS = [Binding("enter", "go", "go on"), Binding("escape", "back", "back")]

    def __init__(self, body):
        super().__init__()
        self.body = body

    def compose(self):
        yield Header()
        yield Static(PlainText.of(self.body), markup=False)
        yield Footer()

    def action_go(self):
        self.dismiss(True)

    def action_back(self):
        self.dismiss(False)

    body = ""
