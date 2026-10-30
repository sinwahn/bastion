import dataclasses


@dataclasses.dataclass
class FirewallFacts:
    station_unknown: bool = False
    has_leg: bool = False
    leg: list = dataclasses.field(default_factory=list)
    has_line: bool = False
    line: list = dataclasses.field(default_factory=list)
    has_internet: bool = False
    internet: list = dataclasses.field(default_factory=list)
    tries: list = dataclasses.field(default_factory=list)


class FirewallCheck:
    """firewall-check inside firewall-vm: a station's leg, its line and its last refused tries."""

    def __init__(self, answer_point):
        self.answer_point = answer_point

    def read(self, name, seconds):
        answers = {}
        facts = FirewallFacts()
        for said in self.answer_point.lines_answering(name + "\n", seconds):
            words = said.split()
            if words and words[0] == "tried":
                facts.tries.append(words[1:])
            elif words:
                answers[words[0]] = words[1:]
        self._fill(facts, answers)
        return facts

    def _fill(self, facts, answers):
        facts.station_unknown = "unknown" in answers
        facts.has_leg = "leg" in answers
        facts.leg = answers.get("leg", [])
        facts.has_line = "line" in answers
        facts.line = answers.get("line", [])
        facts.has_internet = "internet" in answers
        facts.internet = answers.get("internet", [])

    answer_point = None
