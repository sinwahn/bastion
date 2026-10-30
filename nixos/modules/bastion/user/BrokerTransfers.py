from user.ExchangeStepOnScreen import ExchangeStepOnScreen
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.TextScreen import TextScreen


class BrokerTransfers:
    """broker-vm's transfers through the exchange step: its last lines, all or those naming a VM, and a VM's kept copies cleaned."""

    def __init__(self, screen, access):
        self.screen = screen
        self.access = access

    async def show_all(self):
        await self._show([])

    async def show_of(self, name):
        await self._show([name])

    async def clean(self, name):
        """name's kept copies cleaned after Enter, and the files of its stopped sends on the host; the step's lines shown, the count and the bytes."""
        exchange = self.access.configuration.exchange
        picked = await self.screen.app.push_screen_wait(QuestionScreen(Question(
            title=f"{name}: {exchange.clean_action}", choices=[Choice(exchange.clean, exchange.clean_action)])))
        if not picked:
            return
        step = ExchangeStepOnScreen(self.screen.app, self.access)
        step.run([exchange.clean, name])
        self.screen.say(step.said())

    async def _show(self, names):
        configuration = self.access.configuration
        step = ExchangeStepOnScreen(self.screen.app, self.access)
        step.run([configuration.exchange.transfers, str(configuration.transfers_lines)] + names)
        await self.screen.app.push_screen_wait(TextScreen(step.said()))

    screen = None
    access = None
