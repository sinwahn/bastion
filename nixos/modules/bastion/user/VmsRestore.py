from model.LiveDataWriting import LiveDataWriting
from model.NetworksCopy import NetworksCopy
from model.StateReading import StateReading
from model.errors import FileNotDone, LibvirtNotDone
from system.PrivilegedSteps import StepCall
from system.errors import FileFailed, LibvirtCallFailed, StepFailed
from user.AppliedLine import AppliedLine
from user.CopyNotice import CopyNotice
from user.PicksScreen import PicksScreen
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.ScreenSteps import ScreenSteps


class VmsRestore:
    """restore: the VMs saved in the copy folder that libvirt does not hold now, any number picked, then one kind for them all."""

    # A template whose sealed mark exists is left out (restoring it would
    # undo its seal). Definitions only, or whole for the picked VMs that have
    # a state folder, the others then coming back with their definitions
    # only. Whole: state-copy restore first, then the definition; then one
    # networks-write with the restored VMs' stations from the copy. A VM
    # defined now is left as it is.

    def __init__(self, screen, access):
        self.screen = screen
        self.access = access

    async def run(self):
        try:
            self.state = StateReading(self.access).read()
        except LibvirtNotDone as error:
            self.screen.say(f"libvirt cannot be read: {error}")
            return
        defined = {vm.name for vm in self.state.vms}
        saved = self.access.copy_folder.saved_names()
        here = [name for name in saved if name in defined]
        sealed = self.access.templates.sealed_names()
        offered = [name for name in saved if name not in defined and name not in sealed]
        left = f"defined now, left as they are: {', '.join(here)}" if here else ""
        if not offered:
            self.screen.say("no saved VM to restore" + (f"\n{left}" if left else ""))
            return
        await self._ask(offered, left)
        if not self.picked:
            return
        self._restore_picked()
        self.screen.say("\n".join(self.lines))
        self.screen.action_read()
        CopyNotice(self.screen.app, self.access).write()

    async def _ask(self, offered, left):
        has_state = {name: self.access.copy_folder.has_state(name) for name in offered}
        picks = Question(title=f"Restore: the VMs saved in {self.access.configuration.copy_folder} that are not defined now",
                         choices=[Choice(name, f"{name}, with saved firmware and TPM" if has_state[name] else f"{name}, definition only saved")
                                  for name in offered],
                         meaning=(f"{left}\n" if left else "") + "space or Enter picks and unpicks, ctrl+s goes on")
        picked = await self.screen.app.push_screen_wait(PicksScreen(picks, ()))
        if not picked:
            return
        kind = await self.screen.app.push_screen_wait(QuestionScreen(Question(title="Which kind of restore?", choices=[
            Choice("definitions", "definitions only (fresh firmware and TPM)"),
            Choice("whole", "whole (with the saved firmware and TPM)", not any(has_state[name] for name in picked))])))
        if not kind:
            return
        self.whole = kind == "whole"
        self.picked = picked

    def _restore_picked(self):
        self.lines = []
        self.restored = []
        for name in sorted(self.picked):
            self._restore(name)
        if self.restored:
            self._restore_stations()

    def _restore(self, name):
        folder = self.access.copy_folder
        whole = self.whole and folder.has_state(name)
        try:
            definition = folder.saved_definition(name)
            uuid = folder.saved_uuid(definition)
            if whole:
                self._put_state_back(name, uuid)
            self.state.libvirt.define(definition)
        except (FileFailed, LibvirtCallFailed) as error:
            self.lines.append(f"{name}, not restored: {error}")
            return
        except StepFailed as failure:
            output = failure.answer.output
            self.lines.append(f"{name}, not restored: {output.splitlines()[-1] if output else failure.code}")
            return
        self.access.changes.add(name)
        self.restored.append(name)
        self.lines.append(f"{name}, restored whole" if whole else f"{name}, restored, definition only")

    def _put_state_back(self, name, uuid):
        call = StepCall()
        call.step = "state-copy"
        call.arguments = ["restore", name, uuid]
        call.note = f"state-copy puts {name}'s firmware variables and TPM state back (sudo may ask your password) ..."
        ScreenSteps(self.screen.app, self.access.privileged_steps).run(call)

    def _restore_stations(self):
        try:
            saved = self.access.live_format.parse(self.access.copy_folder.saved_live_data())
            live = self.access.live_data_file.read()
        except (FileFailed, FileNotDone) as error:
            self.lines.append(f"no station taken from the copy: {error}")
            return
        result = NetworksCopy().restored(live, saved, self.restored)
        if not result.stations:
            return
        applied = AppliedLine(LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access))
        applied.write(result.content)
        self.lines.append(f"stations added: {', '.join(result.stations)}")
        if result.networks:
            self.lines.append(f"networks added: {', '.join(result.networks)}")
        self.lines.append(applied.line())

    screen = None
    access = None
    state = None
    picked = ()
    whole = False
    lines = ()
    restored = ()
