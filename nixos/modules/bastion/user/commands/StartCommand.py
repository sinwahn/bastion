from model.GlassCommand import GlassCommand
from model.HostThreads import HostThreads
from model.LiveDataWriting import LiveDataWriting
from model.StartPlanning import StartPlanning
from model.StateReading import StateReading
from model.StateVms import StateVms
from model.StationFollow import StationFollow
from model.VmStart import VmStart
from model.errors import LibvirtNotDone
from user.CopyPrint import CopyPrint
from user.FirewallWarning import FirewallWarning
from user.TerminalSteps import TerminalSteps
from user.VmWait import VmWait
from user.enums import ExitCode
from user.errors import Stop


class StartCommand:
    """bastion start and bastion first: NAME started when it does not run, as the start screen starts it without its Enter; then its window and the wait."""

    # The window: the looking-glass window at a start of a VM whose
    # definition holds the glass block, the console otherwise.

    def __init__(self, access, start):
        self.access = access
        self.start = start

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.start.word()

    def run(self, arguments):
        name = arguments[1]
        state = StateReading(self.access).read()
        vms = StateVms(state)
        if not vms.has(name):
            raise Stop(f"STOP: no workstation '{name}' ({self.access.configuration.command} list shows them).")
        vm = vms.vm(name)
        for line in FirewallWarning(self.access).lines():
            print(line, flush=True)
        if state.libvirt.state_word(name) != state.libvirt.kRunningWord:
            self._start(state, vm)
        wait = VmWait(self.access, state.libvirt)
        if vm.glass and self.start.shows_glass():
            wait.wait_showing_glass(name, GlassCommand().words(vm))
        else:
            self.access.windows.open_console(name)
            wait.wait(name)

    def exit_code(self):
        return ExitCode.kDone

    def _start(self, state, vm):
        name = vm.name
        stopped = f"STOP: {name} is not started (the lines of {self.access.configuration.command} {self.start.word()} above)."
        plan = StartPlanning(self.access.configuration).plan(state, vm, self.start)
        if plan.refusals:
            raise Stop(f"{name} cannot start now:\n" + "\n".join(plan.refusals) + "\n" + stopped)
        print("\n".join(plan.lines), flush=True)
        print(f"starting {name} ...", flush=True)
        StationFollow(LiveDataWriting(TerminalSteps(self.access.privileged_steps), self.access), self.access).follow(vm)
        CopyPrint(self.access).write()
        try:
            VmStart(state.libvirt, HostThreads(state.host), self.access.configuration.switch).start(name, plan, self.start)
        except LibvirtNotDone as failure:
            raise Stop(f"{name} did not start: {failure}\nUpload: journalctl -u libvirtd -b --no-pager | tail -n 40"
                       + "\n" + stopped) from failure

    access = None
    start = None
