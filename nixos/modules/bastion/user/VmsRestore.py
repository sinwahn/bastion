from model.LiveDataWriting import LiveDataWriting
from model.NetworksCopy import NetworksCopy
from model.StateReading import StateReading
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
            state = StateReading(self.access).read()
        except LibvirtCallFailed as error:
            self.screen.say(f"libvirt cannot be read: {error}")
            return
        defined = {vm.name for vm in state.vms}
        saved = self.access.copy_folder.saved_names()
        here = [name for name in saved if name in defined]
        sealed = self.access.templates.sealed_names()
        offered = [name for name in saved if name not in defined and name not in sealed]
        left = f"defined now, left as they are: {', '.join(here)}" if here else ""
        if not offered:
            self.screen.say("no saved VM to restore" + (f"\n{left}" if left else ""))
            return
        picked = await self._ask(offered, left)
        if not picked:
            return
        lines, restored = [], []
        for name in sorted(picked):
            if self.whole and self.access.copy_folder.has_state(name):
                lines.append(self._restore_whole(name, restored))
            else:
                lines.append(self._restore_definition(name, restored))
        if restored:
            lines += self._restore_stations(restored)
        self.screen.say("\n".join(lines))
        self.screen.action_read()
        CopyNotice(self.screen.app, self.access).write()

    async def _ask(self, offered, left):
        """The VMs picked, whole noted when that kind is picked; none when a question is left."""
        has_state = {name: self.access.copy_folder.has_state(name) for name in offered}
        picks = Question(title=f"Restore: the VMs saved in {self.access.configuration.copy_folder} that are not defined now",
                         choices=[Choice(name, f"{name}, with saved firmware and TPM" if has_state[name] else f"{name}, definition only saved")
                                  for name in offered],
                         meaning=(f"{left}\n" if left else "") + "space or Enter picks and unpicks, ctrl+s goes on")
        picked = await self.screen.app.push_screen_wait(PicksScreen(picks, ()))
        if not picked:
            return []
        kind = await self.screen.app.push_screen_wait(QuestionScreen(Question(title="Which kind of restore?", choices=[
            Choice("definitions", "definitions only (fresh firmware and TPM)"),
            Choice("whole", "whole (with the saved firmware and TPM)", not any(has_state[name] for name in picked))])))
        if not kind:
            return []
        self.whole = kind == "whole"
        return picked

    def _restore_whole(self, name, restored):
        folder = self.access.copy_folder
        try:
            uuid = folder.saved_uuid(folder.saved_definition(name))
        except FileFailed as error:
            return f"{name}, not restored: {error}"
        call = StepCall(step="state-copy", arguments=["restore", name, uuid],
                        note=f"state-copy puts {name}'s firmware variables and TPM state back "
                             "(sudo may ask your password) ...")
        try:
            ScreenSteps(self.screen.app, self.access.privileged_steps).run(call)
        except StepFailed as failure:
            output = failure.answer.output
            return f"{name}, not restored: {output.splitlines()[-1] if output else failure.code}"
        return self._define(name, restored) or f"{name}, restored whole"

    def _restore_definition(self, name, restored):
        try:
            self.access.copy_folder.saved_uuid(self.access.copy_folder.saved_definition(name))
        except FileFailed as error:
            return f"{name}, not restored: {error}"
        return self._define(name, restored) or f"{name}, restored, definition only"

    def _define(self, name, restored):
        """Empty when name's saved definition is defined again; else the line that says why not."""
        try:
            self.access.libvirt.open().define(self.access.copy_folder.saved_definition(name))
        except (LibvirtCallFailed, FileFailed) as error:
            return f"{name}, not restored: {error}"
        self.access.changes.add(name)
        restored.append(name)
        return ""

    def _restore_stations(self, restored):
        try:
            saved = self.access.live_format.parse(self.access.copy_folder.saved_live_data())
            live = self.access.live_data_file.read()
        except FileFailed as error:
            return [f"no station taken from the copy: {error}"]
        result = NetworksCopy().restored(live, saved, restored)
        if not result.stations:
            return []
        writing = LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access)
        applied = AppliedLine(writing).write(result.content)
        lines = [f"stations added: {', '.join(result.stations)}"]
        if result.networks:
            lines.append(f"networks added: {', '.join(result.networks)}")
        return lines + [applied]

    screen = None
    access = None
    whole = False
