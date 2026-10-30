from system.PrivilegedSteps import StepCall
from system.errors import LibvirtCallFailed, StepFailed
from user.CopyPrint import CopyPrint
from user.TemplateArgument import TemplateArgument
from user.TerminalSteps import TerminalSteps
from user.enums import ExitCode, TemplateWait
from user.errors import Stop


class SealCommand:
    """bastion seal T: when tpl-T is not sealed, the checks, then its sealed mark written by template-seal; then tpl-T undefined keeping its firmware variables and TPM state, when it is still defined."""

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.kWord

    def run(self, arguments):
        template = TemplateArgument(self.access).template(arguments)
        libvirt = self.access.libvirt.open()
        if not self.access.templates.is_sealed(template):
            self._seal(libvirt, template)
        if libvirt.state_word(template.name):
            self._undefine(libvirt, template)
        print(f"{template.name} is sealed: {self.access.configuration.command} makes workstations from it.")

    def exit_code(self):
        return ExitCode.kDone

    def _seal(self, libvirt, template):
        name = template.name
        state = libvirt.state_word(name)
        if not state:
            raise Stop(f"STOP: there is no {name} yet: {self.access.configuration.command} template {template.word}")
        if state != libvirt.kShutOffWord:
            raise Stop(f"STOP: {name} is '{state}', not '{libvirt.kShutOffWord}'.")
        if self.access.files.allocated_kib(template.file) <= TemplateWait.kInstalledKib:
            raise Stop(f"STOP: Windows is not installed in {name}.")
        call = StepCall()
        call.step = "template-seal"
        call.arguments = [template.word]
        try:
            TerminalSteps(self.access.privileged_steps).run(call)
        except StepFailed as failure:
            raise Stop(f"STOP: cannot mark {name} sealed.") from failure

    def _undefine(self, libvirt, template):
        command = self.access.configuration.command
        try:
            libvirt.undefine_keeping_state(template.name)
        except LibvirtCallFailed as failure:
            raise Stop(str(failure) + "\n" + f"STOP: {command} seal {template.word} failed (lines above).") from failure
        self.access.changes.add(template.name)
        print(f"{template.name} is no longer defined; its disk, firmware variables and TPM state stay.")
        CopyPrint(self.access).write()

    access = None
    kWord = "seal"
