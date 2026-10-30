from model.LiveDataWriting import LiveDataWriting
from model.StationEdit import StationEdit
from model.enums import InternetRule
from user.AppliedLine import AppliedLine
from user.NamesScreen import NamesScreen
from user.Question import Choice, Question, RuleAnswer
from user.QuestionScreen import QuestionScreen
from user.ScreenSteps import ScreenSteps


class RuleChange:
    """A VM's internet rule asked and written into its station, for the VM screen and the networks section."""

    def __init__(self, screen, access):
        self.screen = screen
        self.access = access

    async def ask(self, now, names):
        """The internet rule and, for listed, its names; an empty rule when the question is left."""
        question = Question(title="Internet", choices=[
            Choice("open", "open: the whole internet, logged" + (" (now)" if now == "open" else "")),
            Choice("listed", "listed: only the names you type, each on its own line" + (" (now)" if now == "listed" else "")),
            Choice("none", "none: no internet; every try is logged" + (" (now)" if now == "none" else ""))],
            meaning="a change of the internet rule takes effect at once")
        answer = RuleAnswer()
        answer.rule = await self.screen.app.push_screen_wait(QuestionScreen(question))
        if answer.rule != InternetRule.kListed.value:
            return answer
        picked = await self.screen.app.push_screen_wait(NamesScreen("The names it may reach", names))
        if picked is NamesScreen.kBack:
            answer.rule = QuestionScreen.kBack
        else:
            answer.names = picked
        return answer

    async def change(self, name):
        content = self.access.live_data_file.read()
        if name not in content.stations:
            self.screen.say(f"{name} has no entry in networks.json.")
            return
        station = content.stations[name]
        answer = await self.ask(station.rule, station.names)
        if answer.rule == QuestionScreen.kBack:
            return
        StationEdit(self.access.configuration.exchange.sends_to).set_rule(station, answer.rule, answer.names)
        writing = LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access)
        self.screen.say(AppliedLine(writing).write(content))

    screen = None
    access = None
