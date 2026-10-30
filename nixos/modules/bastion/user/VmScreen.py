from textual import work
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import Footer, Header, OptionList, Static
from textual.widgets.option_list import Option

from model.GlassCommand import GlassCommand
from model.StateReading import StateReading
from model.StateVms import StateVms
from model.errors import LibvirtNotDone
from model.starts.FirstStart import FirstStart
from model.starts.OrdinaryStart import OrdinaryStart
from system.errors import LibvirtCallFailed
from user.CopyNotice import CopyNotice
from user.PlainText import PlainText
from user.Question import Choice
from user.RuleChange import RuleChange
from user.VmDiskGrowth import VmDiskGrowth
from user.VmLines import VmLines
from user.VmRetirement import VmRetirement
from user.VmSettingChanges import VmSettingChanges
from user.VmStartOnScreen import VmStartOnScreen
from user.errors import NotSaved


class VmScreen(Screen):
    """One VM: its settings, each changed on its own screen, and its actions."""
    BINDINGS = [Binding("escape", "app.pop_screen", "back")]

    def __init__(self, access, name):
        super().__init__()
        self.access = access
        self.vm_name = name

    def compose(self):
        yield Header()
        yield Static(PlainText.of(""), markup=False, id="details")
        yield OptionList(*[Option(PlainText.of(choice.words), id=choice.identifier) for choice in self.kActions], id="actions")
        yield Static(PlainText.of(""), markup=False, id="message")
        yield Footer()

    def on_mount(self):
        self.sub_title = self.vm_name

    def on_screen_resume(self):
        self.read()

    def say(self, body):
        self.query_one("#message", Static).update(PlainText.of(body))

    def read(self):
        """The VM read again and its details shown, or that libvirt does not hold it."""
        self.state = StateReading(self.access).read()
        vms = StateVms(self.state)
        details = self.query_one("#details", Static)
        if not vms.has(self.vm_name):
            details.update(PlainText.of(f"{self.vm_name} is not in libvirt's store."))
            return
        self.vm = vms.vm(self.vm_name)
        details.update(PlainText.of(VmLines(self.state).details(self.vm)))

    def on_option_list_option_selected(self, event):
        if event.option_list.id == "actions":
            self.act(event.option_id)

    @work(exclusive=True)
    async def act(self, what):
        self.read()
        if not StateVms(self.state).has(self.vm_name):
            return
        try:
            await self._actions()[what](self.vm)
        except (LibvirtNotDone, LibvirtCallFailed) as error:
            self.say(f"not done: {error}")
        except NotSaved as failure:
            self.say(str(failure))
            return
        if what not in self.kLeavingActions:
            self.read()
        CopyNotice(self.app, self.access).write()

    def _actions(self):
        settings = VmSettingChanges(self, self.access, self.state)
        starts = VmStartOnScreen(self, self.access, self.state)
        return {"start": lambda vm: starts.start(vm, OrdinaryStart()), "first": lambda vm: starts.start(vm, FirstStart()),
                "shutdown": self._shut_down, "window": self._open_window, "console": self._open_console,
                "cores": settings.change_cores, "fast": settings.change_fast, "ram": settings.change_ram,
                "disk": VmDiskGrowth(self, self.access, self.state).grow, "graphics": settings.change_graphics,
                "internet": self._change_rule, "retire": VmRetirement(self, self.access, self.state).retire}

    async def _shut_down(self, vm):
        self.state.libvirt.shut_down(vm.name)
        self.say(f"{vm.name} is shutting down: Windows ends by itself.")

    async def _open_window(self, vm):
        if vm.glass and vm.name not in self.access.first_starts:
            self.access.windows.open_glass(GlassCommand().words(vm))
        else:
            self.access.windows.open_console(vm.name)
        self.say(f"{vm.name}'s window opens.")

    async def _open_console(self, vm):
        self.access.windows.open_console(vm.name)
        self.say(f"{vm.name}'s console opens.")

    async def _change_rule(self, vm):
        await RuleChange(self, self.access).change(vm.name)

    access = None
    vm_name = ""
    state = None
    vm = None
    kActions = [Choice("start", "start"), Choice("first", "first start (no network for that start)"),
                Choice("shutdown", "shut down"), Choice("window", "open its window"), Choice("console", "console"),
                Choice("cores", "cores"), Choice("fast", "fast cores first"), Choice("ram", "RAM"), Choice("disk", "disk"),
                Choice("graphics", "graphics"), Choice("internet", "internet rule"), Choice("retire", "retire")]
    # Retire leaves the screen, so nothing is read again after it.
    kLeavingActions = frozenset({"retire"})
