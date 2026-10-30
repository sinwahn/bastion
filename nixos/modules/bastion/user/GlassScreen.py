from textual import work
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, OptionList, Static
from textual.widgets.option_list import Option

from model.Gigabytes import Gigabytes
from model.StateReading import StateReading
from model.StateVms import StateVms
from model.errors import LibvirtNotDone
from user.CopyNotice import CopyNotice
from user.GlassChanges import GlassChanges
from user.PlainText import PlainText
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen


class GlassScreen(Screen):
    """The looking-glass section: glass on or off and the resolution, locked or following the window, for each VM whose definition holds the card, the window's settings in the client's per-user file, and two lines shown read-only."""
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]

    def __init__(self, access):
        super().__init__()
        self.access = access

    def compose(self):
        yield Header()
        yield OptionList(id="glass")
        yield Static(PlainText.of(""), markup=False, id="fixed")
        yield Static(PlainText.of(""), markup=False, id="message")
        yield Static(PlainText.of("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = "looking-glass"

    def on_screen_resume(self):
        self.action_read()

    def say(self, body):
        self.query_one("#message", Static).update(PlainText.of(body))

    def action_read(self):
        listing = self.query_one("#glass", OptionList)
        listing.clear_options()
        self.query_one("#fixed", Static).update(PlainText.of(self._fixed_lines()))
        try:
            state = StateReading(self.access).read()
        except LibvirtNotDone as error:
            self.say(f"libvirt cannot be read: {error}")
            return
        vms = StateVms(state)
        for vm in state.vms:
            if vms.given_card(vm):
                listing.add_option(Option(PlainText.of(self._vm_line(vm)), id=vm.name))
        listing.add_options([Option(PlainText.of(f"{label}: {value}"), id=label)
                             for label, value in self.access.glass_settings.read().items()])

    def on_option_list_option_selected(self, event):
        if self.access.glass_settings.has(event.option_id):
            self.setting(event.option_id)
        else:
            self.pick(event.option_id)

    @work(exclusive=True)
    async def pick(self, name):
        """A VM's line picked: its glass or its resolution."""
        state = StateReading(self.access).read()
        vm = StateVms(state).vm(name)
        what = await self.app.push_screen_wait(QuestionScreen(Question(title=name, choices=[
            Choice("glass", "glass"), Choice("resolution", "resolution")])))
        changes = GlassChanges(self, self.access)
        actions = {"glass": changes.change_glass, "resolution": changes.change_resolution}
        if what in actions:
            await actions[what](state, vm)
        CopyNotice(self.app, self.access).write()

    @work(exclusive=True)
    async def setting(self, label):
        await GlassChanges(self, self.access).change_setting(label)

    def _fixed_lines(self):
        memory = self.access.shared_memory.read()
        shared = "shared screen memory: not on the host"
        if memory.path:
            shared = (f"shared screen memory: {memory.size // Gigabytes.kUnitBytes['MiB']} MiB, set in the host's setup: "
                      "a change is a rebuild, then a restart of the host")
        return shared + "\nclipboard: closed both ways"

    def _vm_line(self, vm):
        resolution = "follows the window"
        if vm.has_station and "resolution" in vm.station.keys:
            resolution = f"locked at {vm.station.resolution}"
        return (f"{vm.name}, glass: {'on' if vm.glass else 'off'}, resolution: " + resolution
                + (", defined by Nix, which rewrites it at every boot" if vm.nix else ""))

    access = None
