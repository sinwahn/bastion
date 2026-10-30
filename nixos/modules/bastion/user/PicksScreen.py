from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, SelectionList, Static
from textual.widgets.selection_list import Selection

from user.PlainText import PlainText


class PicksScreen(Screen):
    """Any number of choices picked on one screen; dismissed with the ids picked (none is an answer), or kBack."""

    # Space or Enter picks and unpicks (textual's SelectionList), ctrl+s goes
    # on. The ids in picked start picked (a Selection's initial state).
    BINDINGS = [Binding("escape", "back", "back"), Binding("ctrl+s", "go", "go on")]

    def __init__(self, question, picked):
        super().__init__()
        self.question = question
        self.picked = picked

    def compose(self):
        yield Header()
        yield Static(PlainText.of(self.question.title), markup=False, classes="question")
        yield SelectionList(*[Selection(PlainText.of(choice.words), choice.identifier, choice.identifier in self.picked)
                              for choice in self.question.choices])
        if self.question.meaning:
            yield Static(PlainText.of(self.question.meaning), markup=False)
        yield Footer()

    def action_go(self):
        self.dismiss(self.query_one(SelectionList).selected)

    def action_back(self):
        self.dismiss(self.kBack)

    question = None
    picked = ()
    kBack = False
