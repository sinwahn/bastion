from model.HostThreads import HostThreads
from model.LiveDataWriting import LiveDataWriting
from model.StartPlanning import StartPlanning
from model.StationFollow import StationFollow
from model.VmStart import VmStart
from model.errors import LibvirtNotDone
from user.FirewallWarning import FirewallWarning
from user.ScreenSteps import ScreenSteps
from user.TextScreen import TextScreen
from user.VmWait import VmWait


class VmStartOnScreen:
    """A start from the VM screen: its plan shown, Enter starts it, then the command line's start or first runs its window and its wait."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def start(self, vm, start):
        if vm.active:
            self.screen.say(f"{vm.name} runs already.")
            return
        plan = StartPlanning(self.access.configuration).plan(self.state, vm, start)
        if plan.refusals:
            await self._wait(TextScreen(f"{vm.name} cannot start now:\n" + "\n".join(plan.refusals)))
            return
        lines = plan.lines + FirewallWarning(self.access).lines()
        if not await self._wait(TextScreen("\n".join(lines) + "\n\nEnter: start it.")):
            return
        # The line is on the screen before the start, which holds the event
        # loop until it ends: wait_for_refresh returns once the screen is
        # refreshed (textual 8.2.6 message_pump.py 469-488, screen.py 1236-1262).
        self.screen.say(f"starting {vm.name} ...")
        await self.screen.wait_for_refresh()
        follow = StationFollow(LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access), self.access)
        follow.follow(vm)
        try:
            VmStart(self.state.libvirt, HostThreads(self.state.host), self.access.configuration.switch).start(vm.name, plan, start)
        except LibvirtNotDone as failure:
            self.screen.say(f"not started: {failure}")
            return
        start.remember(self.access.first_starts, vm.name)
        self._start_wait(vm, start)
        said = f"{vm.name} runs on {HostThreads(self.state.host).kinds_text(plan.pins)}. {VmWait.kLidWarning}"
        self.screen.say(said + self._follow_line(follow.outcome()))

    def _start_wait(self, vm, start):
        # Its window and the wait: the command line's start or first, a
        # process of its own in a session of its own, which finds the VM
        # running, so it opens the window and holds sleep off until the VM is
        # off, whether these screens stay open or not.
        configuration = self.access.configuration
        self.access.shell.start_detached([configuration.interpreter, configuration.entry, configuration.settings_file,
                                          start.word(), vm.name])

    def _follow_line(self, outcome):
        if not outcome.moved:
            return ""
        return ("\nsaved and applied: " if outcome.applied else "\nnot applied: ") + outcome.output

    async def _wait(self, screen):
        return await self.screen.app.push_screen_wait(screen)

    screen = None
    access = None
    state = None
