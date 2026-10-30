from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, OptionList, Static
from textual.widgets.option_list import Option

from user.PlainText import PlainText


class QuestionScreen(Screen):
    """One question on its own screen; dismissed with the picked id, or kBack."""
    BINDINGS = [Binding("escape", "back", "back")]

    def __init__(self, question):
        super().__init__()
        self.question = question

    def compose(self):
        yield Header()
        yield Static(PlainText.of(self.question.title), markup=False, classes="question")
        if self.question.above:
            yield Static(PlainText.of(self.question.above), markup=False)
        yield OptionList(*[Option(PlainText.of(choice.words), id=choice.identifier, disabled=choice.disabled)
                           for choice in self.question.choices])
        if self.question.meaning:
            yield Static(PlainText.of(self.question.meaning), markup=False)
        yield Footer()

    def on_option_list_option_selected(self, event):
        self.dismiss(event.option_id)

    def action_back(self):
        self.dismiss(self.kBack)

    question = None
    kBack = ""
