from textual import work
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, OptionList, Static
from textual.widgets.option_list import Option

from model.StateReading import StateReading
from model.StateVms import StateVms
from model.errors import LibvirtNotDone
from system.errors import LibvirtCallFailed
from user.CopyNotice import CopyNotice
from user.NetworkLines import NetworkLines
from user.NetworkMaking import NetworkMaking
from user.NewNetworkQuestions import NewNetworkQuestions
from user.PathScreen import PathScreen
from user.PlainText import PlainText
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.ReachChange import ReachChange
from user.RuleChange import RuleChange
from user.StationMove import StationMove


class NetworksScreen(Screen):
    """The networks of the live data file, each with its VMs; a network picked switches whether its VMs reach each other; a VM picked changes its internet rule, moves to a network or shows its path check; and a new network, made while the system runs."""
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]

    def __init__(self, access):
        super().__init__()
        self.access = access

    def compose(self):
        yield Header()
        yield OptionList(id="networks")
        yield OptionList(*[Option(PlainText.of(choice.words), id=choice.identifier) for choice in self.kActions], id="actions")
        yield Static(PlainText.of(""), markup=False, id="message")
        yield Static(PlainText.of("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = "networks"

    def on_screen_resume(self):
        self.action_read()

    def say(self, body):
        self.query_one("#message", Static).update(PlainText.of(body))

    def action_read(self):
        listing = self.query_one("#networks", OptionList)
        listing.clear_options()
        try:
            state = StateReading(self.access).read()
        except LibvirtNotDone as error:
            self.say(f"libvirt cannot be read: {error}")
            return
        if state.failure.failed:
            self.say(f"networks.json cannot be read ({state.failure.reason}).")
            return
        lines = NetworkLines(state, self.access.configuration)
        for network in state.content.networks:
            names = sorted(name for name, station in state.content.stations.items() if station.network == network)
            listing.add_option(Option(PlainText.of(lines.network(network, len(names))), id=self.kNetworkMark + network))
            listing.add_options([Option(PlainText.of(lines.station(name)), id=name) for name in names])

    def on_option_list_option_selected(self, event):
        if event.option_list.id == "actions":
            self.new_network()
        elif event.option_id.startswith(self.kNetworkMark):
            self.switch(event.option_id.removeprefix(self.kNetworkMark))
        else:
            self.pick(event.option_id)

    @work(exclusive=True)
    async def switch(self, name):
        await ReachChange(self, self.access).change(name)
        self.action_read()
        CopyNotice(self.app, self.access).write()

    @work(exclusive=True)
    async def pick(self, name):
        state = StateReading(self.access).read()
        vms = StateVms(state)
        choices = [Choice("internet", "internet rule")]
        if vms.has(name) and not vms.vm(name).nix:
            choices.append(Choice("move", "move to a network"))
        choices.append(Choice("path", "path check"))
        what = await self.app.push_screen_wait(QuestionScreen(Question(
            title=name, choices=choices, above=NetworkLines(state, self.access.configuration).station(name))))
        actions = {"internet": self._change_rule, "move": self._move, "path": self._show_path}
        try:
            if what in actions:
                await actions[what](state, name)
        except (LibvirtNotDone, LibvirtCallFailed) as error:
            self.say(f"not done: {error}")
        self.action_read()
        CopyNotice(self.app, self.access).write()

    @work(exclusive=True)
    async def new_network(self):
        state = StateReading(self.access).read()
        if state.failure.failed:
            self.say(f"networks.json cannot be read ({state.failure.reason}).")
            return
        questions = NewNetworkQuestions(self, self.access, state)
        await questions.ask()
        if not questions.answered().name:
            return
        try:
            NetworkMaking(self, self.access, state).make(questions.answered())
        except (LibvirtNotDone, LibvirtCallFailed) as error:
            self.say(f"not done: {error}")
        self.action_read()
        CopyNotice(self.app, self.access).write()

    async def _change_rule(self, state, name):
        await RuleChange(self, self.access).change(name)

    async def _move(self, state, name):
        await StationMove(self, self.access, state).move(StateVms(state).vm(name))

    async def _show_path(self, state, name):
        self.app.push_screen(PathScreen(self.access, name))

    access = None
    kActions = [Choice("new", "new network")]
    # A network's entry in the list: its id, which no VM's name can be (a
    # name holds no space).
    kNetworkMark = "network "
