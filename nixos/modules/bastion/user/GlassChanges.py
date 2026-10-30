from model.DefinitionEdit import DefinitionEdit
from model.DisplayModes import DisplayModes
from model.HostThreads import HostThreads
from model.LiveDataWriting import LiveDataWriting
from model.Redefinition import Redefinition
from model.StateReading import StateReading
from model.StateVms import StateVms
from model.StationEdit import StationEdit
from model.errors import FileNotDone, LibvirtNotDone
from user.AppliedLine import AppliedLine
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.ScreenSteps import ScreenSteps
from user.VmLines import VmLines
from user.errors import NotSaved


class GlassChanges:
    """The looking-glass section's changes: a VM's glass, its resolution, and a setting of the window."""

    def __init__(self, screen, access):
        self.screen = screen
        self.access = access

    async def change_resolution(self, state, vm):
        """The screen size the VM's Windows is locked at, or following the window, kept in its station as the key resolution, WIDTHxHEIGHT, absent for following."""
        # The sizes offered: the driver's list, each that fits the shared
        # memory read from the host.
        if state.failure.failed:
            self.screen.say(f"networks.json cannot be read ({state.failure.reason}).")
            return
        content = state.content
        if vm.name not in content.stations:
            self.screen.say(f"{vm.name} has no entry in networks.json.")
            return
        station = content.stations[vm.name]
        locked = "resolution" in station.keys
        picked = await self._ask(Question(title=f"{vm.name}: resolution", choices=[
            Choice("follows", "follows the window" + (" (now)" if not locked else ""))]
            + [Choice(size, size + (" (now)" if locked and size == station.resolution else "")) for size in self._sizes()],
            meaning="locked: Windows keeps this size whatever the glass window does; it takes effect after "
                    "the VM's next presets run and restart of Windows. follows the window: Windows takes "
                    "the window's size, as today."))
        if not picked:
            return
        self._set_resolution(station, picked)
        applied = AppliedLine(LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access))
        applied.write(content)
        self.screen.say(applied.line())
        self.screen.action_read()

    async def change_glass(self, state, vm):
        """Glass on or off for one VM, written into its definition."""
        picked = await self._ask(Question(title=f"{vm.name}: glass", choices=[
            Choice("on", "on" + (" (now)" if vm.glass else "")), Choice("off", "off" + (" (now)" if not vm.glass else ""))],
            meaning="on: the VM's screen opens in a window on the host through looking-glass. "
                    "off: no looking-glass window; the console opens instead. "
                    "Takes effect at the VM's next start."))
        if not picked:
            return
        changes = {"on": self._turn_glass_on, "off": self._turn_glass_off}
        try:
            changes[picked](state, vm.name)
            after = StateVms(StateReading(self.access).read()).vm(vm.name)
        except NotSaved as failure:
            self.screen.say(str(failure))
            return
        except LibvirtNotDone as error:
            self.screen.say(f"not done: {error}")
            return
        self.screen.say(VmLines(state).saved(after, f"glass {'on' if after.glass else 'off'}"))
        self.screen.action_read()

    async def change_setting(self, label):
        """One of the window's settings, written into the per-user file."""
        settings = self.access.glass_settings
        now = settings.read()[label]
        picked = await self._ask(Question(title=label.capitalize(), choices=[
            Choice(value, value + (" (now)" if value == now else "")) for value in settings.option(label).offered()],
            meaning="takes effect at the next window opened"))
        if not picked:
            return
        try:
            settings.write(label, picked)
        except FileNotDone as error:
            self.screen.say(f"not saved: {error}")
            return
        self.screen.say(f"saved: {label} {settings.read()[label]}")
        self.screen.action_read()

    def _sizes(self):
        memory = self.access.shared_memory.read()
        if not memory.path:
            return []
        return DisplayModes().fitting(memory.size)

    def _set_resolution(self, station, picked):
        stations = StationEdit(self.access.configuration.exchange.sends_to)
        if picked == "follows":
            stations.drop_resolution(station)
        else:
            stations.set_resolution(station, picked)

    def _turn_glass_on(self, state, name):
        memory = self.access.shared_memory.read()
        if not memory.path:
            raise NotSaved("not saved: looking-glass's shared memory is not on the host.")
        edit = DefinitionEdit(HostThreads(state.host))
        Redefinition(state.libvirt, self.access.changes).apply(name, lambda root: edit.set_glass(root, memory))

    def _turn_glass_off(self, state, name):
        edit = DefinitionEdit(HostThreads(state.host))
        Redefinition(state.libvirt, self.access.changes).apply(name, edit.drop_glass)

    async def _ask(self, question):
        return await self.screen.app.push_screen_wait(QuestionScreen(question))

    screen = None
    access = None
