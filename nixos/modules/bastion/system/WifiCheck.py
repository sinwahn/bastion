import dataclasses


@dataclasses.dataclass
class UplinkFact:
    state: str = ""
    permission: str = ""
    metric: str = ""


@dataclasses.dataclass
class WifiFacts:
    uplinks: dict = dataclasses.field(default_factory=dict)
    route: list = dataclasses.field(default_factory=list)
    card: list = dataclasses.field(default_factory=list)


class WifiCheck:
    """wifi-check inside wifi-vm: each uplink's facts there by its name, wifi-vm's way out and its Wi-Fi card."""

    def __init__(self, answer_point):
        self.answer_point = answer_point

    def read(self, seconds):
        said = self.answer_point.lines(seconds)
        facts = WifiFacts()
        for words in (line.split() for line in said):
            if len(words) >= 5 and words[0] == "uplink":
                facts.uplinks[words[1]] = self._uplink_fact(words)
        facts.route = next((line.split()[1:] for line in said if line.startswith("route ")), [])
        facts.card = next((line.split(None, 2) for line in said if line.startswith("wifi ")), [])
        return facts

    def _uplink_fact(self, words):
        fact = UplinkFact()
        fact.state = words[2]
        fact.permission = words[3]
        fact.metric = words[4]
        return fact

    answer_point = None
