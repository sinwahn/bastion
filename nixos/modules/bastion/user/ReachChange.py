from model.CableEdit import CableEdit
from model.LiveDataWriting import LiveDataWriting
from model.Redefinition import Redefinition
from model.StateReading import StateReading
from model.errors import LibvirtNotDone
from user.AppliedLine import AppliedLine
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.ScreenSteps import ScreenSteps


class ReachChange:
    """A network's reach-each-other: networks-write first, then the definition of every VM it puts on the network, from the value read back."""

    def __init__(self, screen, access):
        self.screen = screen
        self.access = access

    async def change(self, name):
        content = self.access.live_data_file.read()
        entry = content.networks[name]
        now = entry.reach_each_other
        firewall = self.access.configuration.firewall_vm
        picked = await self.screen.app.push_screen_wait(QuestionScreen(Question(
            title=f"{name}: VMs reach each other",
            choices=[Choice("yes", "yes" + (" (now)" if now else "")), Choice("no", "no" + (" (now)" if not now else ""))],
            meaning=f"yes: the VMs on {name} reach each other directly, as on a switch of their own. "
                    f"no: each VM on {name} reaches only {firewall}. Takes effect at once.")))
        if not picked:
            return
        entry.reach_each_other = picked == "yes"
        applied = AppliedLine(LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access))
        applied.write(content)
        try:
            state = StateReading(self.access).read()
        except LibvirtNotDone as error:
            self.screen.say(applied.line() + f"\nnot done: {error}")
            return
        self._set_cables_again(state, name)
        self.screen.say(applied.line() + "".join(self.not_done))

    def _set_cables_again(self, state, name):
        edit = CableEdit(self.access.configuration.switch)
        redefinition = Redefinition(state.libvirt, self.access.changes)
        self.not_done = []
        for vm in state.vms:
            if edit.network_of(vm.root, state.content) != name:
                continue
            try:
                redefinition.apply(vm.name, lambda root: edit.set_lane(root, state.content, name))
            except LibvirtNotDone as error:
                self.not_done.append(f"\nnot done: {vm.name}: {error}")

    screen = None
    access = None
    not_done = ()
