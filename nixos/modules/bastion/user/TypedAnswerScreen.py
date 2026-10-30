from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, Input, Static

from user.PlainText import PlainText


class TypedAnswerScreen(Screen):
    """A typed answer, checked on the spot; a refusal stays on the screen; Escape dismisses kBack."""
    BINDINGS = [Binding("escape", "back", "back")]

    def __init__(self, question, check):
        super().__init__()
        self.question = question
        self.check = check

    def compose(self):
        yield Header()
        yield Static(PlainText.of(self.question.title), markup=False, classes="question")
        yield Input()
        yield Static(PlainText.of(""), markup=False, id="reason")
        yield Static(PlainText.of(self.question.meaning), markup=False)
        yield Footer()

    def on_input_submitted(self, event):
        value = event.value.strip()
        reason = self.check(value)
        if reason:
            self.query_one("#reason", Static).update(PlainText.of(f"refused: {reason}"))
        else:
            self.dismiss(value)

    def action_back(self):
        self.dismiss(self.kBack)

    question = None
    check = None
    kBack = ""
