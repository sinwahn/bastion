from textual import work
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, OptionList, Static
from textual.widgets.option_list import Option

from model.StateReading import StateReading
from model.StateVms import StateVms
from model.errors import LibvirtNotDone
from user.BrokerLines import BrokerLines
from user.BrokerTransfers import BrokerTransfers
from user.BrokerUsage import BrokerUsage
from user.CopyNotice import CopyNotice
from user.DestinationsChange import DestinationsChange
from user.FileSending import FileSending
from user.PlainText import PlainText
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen


class BrokerScreen(Screen):
    """The broker section: broker-vm's line with its kept copies, then each VM the tool owns with the VMs it may send files to, then the section's two actions, send a file and transfers."""

    # A VM picked changes its list (written by networks-write with no
    # rebuild), sends a file when it runs, shows its transfers or cleans its
    # kept copies. The host has no line: it only receives. The figures of the
    # kept copies are read through the exchange step when the section opens
    # and at r.
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]

    def __init__(self, access):
        super().__init__()
        self.access = access

    def compose(self):
        exchange = self.access.configuration.exchange
        yield Header()
        yield Static(PlainText.of(""), markup=False, id="broker")
        yield OptionList(id="vms")
        yield OptionList(Option(PlainText.of(exchange.send_action), id=exchange.send),
                         Option(PlainText.of(exchange.transfers), id=exchange.transfers), id="actions")
        yield Static(PlainText.of(""), markup=False, id="message")
        yield Static(PlainText.of("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = self.access.configuration.exchange.section
        self.first_read = False

    def on_screen_resume(self):
        self._list_vms()
        if not self.first_read:
            self.first_read = True
            self.call_after_refresh(self._read_first)

    def say(self, body):
        self.query_one("#message", Static).update(PlainText.of(body))

    def action_read(self):
        self._read_first()
        self._list_vms()

    def on_option_list_option_selected(self, event):
        if event.option_list.id != "actions":
            self._pick(event.option_id)
        elif event.option_id == self.access.configuration.exchange.send:
            self._send_any()
        else:
            self._show_transfers()

    def _read_first(self):
        usage = BrokerUsage(self.app, self.access)
        usage.read()
        for message in usage.messages():
            self.say(message)
        self.query_one("#broker", Static).update(PlainText.of(usage.line()))

    def _list_vms(self):
        listing = self.query_one("#vms", OptionList)
        listing.clear_options()
        try:
            state = StateReading(self.access).read()
        except LibvirtNotDone as error:
            self.say(f"libvirt cannot be read: {error}")
            return
        if state.failure.failed:
            self.say(f"networks.json cannot be read ({state.failure.reason}).")
            return
        lines = BrokerLines(state, self.access.configuration)
        listing.add_options([Option(PlainText.of(lines.line(vm)), id=vm.name) for vm in lines.vms()])

    @work(exclusive=True)
    async def _pick(self, name):
        # A VM's line picked: its list of destinations, a file sent when it
        # runs, its transfers, its kept copies cleaned.
        state = StateReading(self.access).read()
        vm = StateVms(state).vm(name)
        exchange = self.access.configuration.exchange
        choices = [Choice(exchange.sends_to, exchange.sends_to_label)]
        if vm.active:
            choices.append(Choice(exchange.send, exchange.send_action))
        choices += [Choice(exchange.transfers, exchange.transfers), Choice(exchange.clean, exchange.clean_action)]
        what = await self.app.push_screen_wait(QuestionScreen(Question(
            title=name, choices=choices, above=BrokerLines(state, self.access.configuration).line(vm))))
        transfers = BrokerTransfers(self, self.access)
        actions = {exchange.sends_to: DestinationsChange(self, self.access, state).change,
                   exchange.send: FileSending(self, self.access, state).send_from,
                   exchange.transfers: lambda picked: transfers.show_of(picked.name),
                   exchange.clean: lambda picked: transfers.clean(picked.name)}
        if what in actions:
            await actions[what](vm)
        self._list_vms()
        CopyNotice(self.app, self.access).write()

    @work(exclusive=True)
    async def _send_any(self):
        await FileSending(self, self.access, StateReading(self.access).read()).send_any()
        self._list_vms()

    @work(exclusive=True)
    async def _show_transfers(self):
        await BrokerTransfers(self, self.access).show_all()

    access = None
    first_read = False
