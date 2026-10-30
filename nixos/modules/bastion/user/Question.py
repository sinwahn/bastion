import dataclasses


@dataclasses.dataclass
class Choice:
    """One answer of a question: its id, its words, and whether it can be picked."""
    identifier: str = ""
    words: str = ""
    disabled: bool = False


@dataclasses.dataclass
class RuleAnswer:
    """An internet rule answered, and for listed its names; rule empty when the question is left."""
    rule: str = ""
    names: list = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class Question:
    """A question on its own screen: its title, its choices, a line above them and a line of meaning below."""
    title: str = ""
    choices: list = dataclasses.field(default_factory=list)
    above: str = ""
    meaning: str = ""
