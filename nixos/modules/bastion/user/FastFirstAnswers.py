from model.enums import ThreadKind
from model.preferences.DenseFirst import DenseFirst
from model.preferences.FastFirst import FastFirst


class FastFirstAnswers:
    """The answers yes and no of the question fast cores first, and the core order each picks."""

    def preference(self, answer):
        return self.kPreferences[answer]

    def answer(self, preference):
        """The answer that picks preference: yes for fast first, no for dense first."""
        return self.kAnswers[preference.word()]

    kPreferences = {"yes": FastFirst(), "no": DenseFirst()}
    kAnswers = {ThreadKind.kFast.value: "yes", ThreadKind.kDense.value: "no"}
