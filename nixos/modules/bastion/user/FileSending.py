from model.StateVms import StateVms
from user.BrokerLines import BrokerLines
from user.ExchangeStepOnScreen import ExchangeStepOnScreen
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen


class FileSending:
    """A file of a running VM's Outbox sent through the exchange step to a destination of its list that runs, or to the host."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def send_any(self):
        """The section's send a file: a running VM picked, then as a VM's send a file."""
        lines = BrokerLines(self.state, self.access.configuration)
        name = await self._ask(Question(title=self.access.configuration.exchange.send_action, choices=[
            Choice(vm.name, lines.line(vm)) for vm in lines.vms() if vm.active]))
        if name:
            await self.send_from(StateVms(self.state).vm(name))

    async def send_from(self, vm):
        """A file of vm's Outbox, read live through the exchange step, picked; then a destination; Enter sends, the step's lines shown."""
        exchange = self.access.configuration.exchange
        outbox = ExchangeStepOnScreen(self.screen.app, self.access)
        outbox.run([exchange.outbox_folder, vm.name])
        if not outbox.ran_well():
            self.screen.say(outbox.said())
            return
        title = f"{vm.name}: {exchange.send_action}"
        file = await self._ask(Question(title=title, choices=[Choice(name, name) for name in outbox.lines()]))
        if not file:
            return
        target = await self._ask(Question(title=f"{title}: {file}", choices=[Choice(name, name) for name in self._destinations(vm)]))
        if not target:
            return
        sending = ExchangeStepOnScreen(self.screen.app, self.access)
        sending.run([exchange.send, vm.name, file, target])
        self.screen.say(sending.said())

    def _destinations(self, vm):
        host = self.access.configuration.host_port
        running = {other.name for other in StateVms(self.state).running()}
        names = vm.station.destinations if vm.has_station else []
        return [name for name in names if name == host or name in running]

    async def _ask(self, question):
        return await self.screen.app.push_screen_wait(QuestionScreen(question))

    screen = None
    access = None
    state = None
