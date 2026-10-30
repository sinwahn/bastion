from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, Static, TextArea

from user.PlainText import PlainText


class NamesScreen(Screen):
    """The listed names, one per line; ctrl+s dismisses them, Escape kBack."""
    BINDINGS = [Binding("escape", "back", "back"), Binding("ctrl+s", "save", "save")]

    def __init__(self, title, names):
        super().__init__()
        self.title_words = title
        self.names = names

    def compose(self):
        yield Header()
        yield Static(PlainText.of(self.title_words), markup=False, classes="question")
        yield TextArea("\n".join(self.names))
        yield Static(PlainText.of(""), markup=False, id="reason")
        yield Static(PlainText.of("one name per line (its subdomains are included); ctrl+s saves"), markup=False)
        yield Footer()

    def action_save(self):
        names = [name.strip() for name in self.query_one(TextArea).text.splitlines() if name.strip()]
        bad = [name for name in names if not all(c.isascii() and (c.isalnum() or c in ".-") for c in name)]
        if bad:
            self.query_one("#reason", Static).update(PlainText.of(f"refused: not a name: {', '.join(bad)}"))
            return
        self.dismiss(names)

    def action_back(self):
        self.dismiss(self.kBack)

    title_words = ""
    names = ()
    kBack = False
