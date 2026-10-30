from model.Gigabytes import Gigabytes
from model.Offers import Offers
from system.PrivilegedSteps import StepCall
from system.errors import StepFailed
from user.HostLines import HostLines
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.ScreenSteps import ScreenSteps


class VmDiskGrowth:
    """A VM's disk made bigger, never smaller: libvirt grows a running VM's disk, disk-grow an off VM's."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def grow(self, vm):
        offers = Offers(self.access.configuration)
        room = offers.disk_room(self.state.host, self.state.vms)
        current = vm.capacity // Gigabytes.kGib
        sizes = offers.growth_sizes(current, room)
        if not sizes:
            self.screen.say(f"{vm.name}'s disk cannot grow: {max(room, 0) // Gigabytes.kGib} GB are free for VM disks.")
            return
        picked = await self.screen.app.push_screen_wait(QuestionScreen(Question(
            title="Disk", choices=[Choice(str(size), f"{size} GB") for size in sizes],
            above=f"now {current} GB; " + HostLines(self.state, self.access.configuration).disk(),
            meaning="bigger only: a disk is never made smaller; C: is extended inside Windows "
                    "by the presets script 70-grow-c")))
        if not picked:
            return
        if vm.active:
            self._grow_running(vm, int(picked))
        else:
            self._grow_off(vm, int(picked))

    def _grow_running(self, vm, size):
        libvirt = self.state.libvirt
        libvirt.resize_disk(vm.name, vm.disk_target, size * Gigabytes.kGib)
        grown = libvirt.disk_sizes(vm.name, vm.disk_target).capacity
        self.screen.say(f"{vm.name}'s disk is {grown // Gigabytes.kGib} GB now; "
                        "extend C: inside Windows (70-grow-c).")

    def _grow_off(self, vm, size):
        steps = ScreenSteps(self.screen.app, self.access.privileged_steps)
        call = StepCall()
        call.step = "disk-grow"
        call.arguments = [vm.name, str(size)]
        try:
            steps.run(call)
        except StepFailed as failure:
            self.screen.say(f"not grown: {failure.answer.output}")
            return
        self.screen.say(steps.last_answer().output)

    screen = None
    access = None
    state = None
