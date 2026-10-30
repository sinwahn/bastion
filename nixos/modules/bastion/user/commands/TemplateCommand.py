import glob
import os
import time

from model.errors import LibvirtNotDone
from system.PrivilegedSteps import StepCall
from system.enums import LinuxKeyCode, WaitSeconds
from system.errors import LibvirtCallFailed, StepFailed
from user.CopyPrint import CopyPrint
from user.FirewallWarning import FirewallWarning
from user.TemplateArgument import TemplateArgument
from user.TemplateDefinition import TemplateDefinition
from user.TerminalSteps import TerminalSteps
from user.VmWait import VmWait
from user.enums import ExitCode, TemplateWait
from user.errors import Stop


class TemplateCommand:
    """bastion template T: Windows Setup in tpl-T, step by step."""

    # Its Windows .iso copied in place from ~/Downloads by make-disk when it
    # is not there, tpl-T defined when it is not, the firewall-vm warning,
    # its console, its start with Space pressed once a second for 30 seconds
    # for "Press any key to boot from CD or DVD" when it does not run, the
    # wait.

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.kWord

    def run(self, arguments):
        template = TemplateArgument(self.access).template(arguments)
        name = template.name
        if self.access.templates.is_sealed(template):
            raise Stop(f"STOP: {name} is sealed; {self.access.configuration.command} makes its workstations.")
        disk_made = not self.access.files.exists(template.iso)
        if disk_made:
            self._copy_iso(template)
        libvirt = self.access.libvirt.open()
        definition = TemplateDefinition(self.access)
        if not libvirt.state_word(name) and disk_made:
            self._define(libvirt, template, definition.define)
        elif not libvirt.state_word(name):
            self._define(libvirt, template, definition.make_disk_and_define)
        for line in FirewallWarning(self.access).lines():
            print(line, flush=True)
        self.access.windows.open_console(name)
        if libvirt.state_word(name) != libvirt.kRunningWord:
            self._start(libvirt, name)
        VmWait(self.access, libvirt).wait(name)

    def exit_code(self):
        return ExitCode.kDone

    def _copy_iso(self, template):
        # Files beginning with a dot are not matched, as in the shell
        # (CPython 3.13 Doc/library/glob.rst 32-34, escape 119).
        pattern = os.path.join(os.path.expanduser("~"), self.kDownloads, f"*{glob.escape(template.download)}*.iso")
        found = self.access.files.matching(pattern)
        if not found:
            raise Stop(f"STOP: no .iso with {template.download} in its name in Downloads.")
        if len(found) > 1:
            raise Stop(f"STOP: more than one .iso with {template.download} in its name in Downloads: {', '.join(found)}")
        print(f"Copying {os.path.basename(found[0])} (a few minutes) ...", flush=True)
        call = StepCall()
        call.step = "make-disk"
        call.arguments = [template.word, found[0]]
        try:
            TerminalSteps(self.access.privileged_steps).run(call)
        except StepFailed as failure:
            raise Stop("STOP: make-disk failed (lines above).") from failure
        self.access.files.remove(found[0])

    def _define(self, libvirt, template, defining):
        try:
            defining(template)
        except (LibvirtCallFailed, LibvirtNotDone) as error:
            print(error)
        if not libvirt.state_word(template.name):
            raise Stop(f"STOP: {template.name} is not defined (the lines of {self.access.configuration.command} template above).")
        CopyPrint(self.access).write()

    def _start(self, libvirt, name):
        time.sleep(TemplateWait.kConsoleSeconds)
        try:
            libvirt.create(name)
        except LibvirtCallFailed as failure:
            raise Stop(f"STOP: {name} does not start: {failure}.") from failure
        for _ in range(TemplateWait.kKeyPresses):
            time.sleep(WaitSeconds.kKeyPress)
            try:
                libvirt.press_key(name, LinuxKeyCode.kSpace)
            except LibvirtCallFailed as failure:
                self.access.log.note(f"a press of Space on {name} is passed over: {failure}")

    access = None
    kWord = "template"
    # The folder of the user's home the template's Windows .iso is taken from.
    kDownloads = "Downloads"
