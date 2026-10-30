import os

from model.LiveDataWriting import LiveDataWriting
from model.errors import LiveDataNotApplied
from system.PrivilegedSteps import StepCall
from system.errors import StepFailed
from user.ScreenSteps import ScreenSteps
from user.TextScreen import TextScreen


class VmRetirement:
    """A VM retired after Enter: disk-retire moves its files into the retired folder, libvirt forgets it keeping its firmware variables and TPM state, its station leaves the live data file."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def retire(self, vm):
        if vm.active:
            self.screen.say(f"{vm.name} runs: shut it down first.")
            return
        where = os.path.join(self.access.configuration.retired_folder, vm.name)
        ip = vm.station.ip if vm.has_station else "-"
        if not await self.screen.app.push_screen_wait(TextScreen(
                f"Retire {vm.name}?\nIt leaves the list. Its disk, its definition, its firmware variables and "
                f"its TPM state are moved into {where}; nothing is deleted. Its address {ip} becomes free "
                "for a new VM.\n\nEnter: retire it.")):
            return
        steps = ScreenSteps(self.screen.app, self.access.privileged_steps)
        call = StepCall()
        call.step = "disk-retire"
        call.arguments = [vm.name]
        try:
            steps.run(call)
        except StepFailed as failure:
            self.screen.say(f"not retired: {failure.answer.output}")
            return
        retired = steps.last_answer().output
        self.state.libvirt.undefine_keeping_state(vm.name)
        self.access.changes.add(vm.name)
        self._free_station(vm.name)
        self.screen.app.pop_screen()
        self.screen.app.notify(f"{vm.name} is retired into {where}. {self.not_freed or retired}")

    def _free_station(self, name):
        content = self.access.live_data_file.read()
        if name not in content.stations:
            return
        del content.stations[name]
        try:
            LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access).write(content)
        except LiveDataNotApplied as failure:
            self.not_freed = f"its address was not freed: {failure}"

    screen = None
    access = None
    state = None
    not_freed = ""
