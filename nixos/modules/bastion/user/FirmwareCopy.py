from model.StateReading import StateReading
from system.errors import FileFailed, LibvirtCallFailed, StepFailed


class FirmwareCopy:
    """copy firmware and TPM: state-copy save for every VM the tool owns, the terminal given back once for them all, so sudo can ask there."""

    # Every VM of libvirt's store that Nix does not define; a running VM is
    # named and skipped, since QEMU and swtpm write those files while it runs.
    # One line per VM: copied, or the failure.

    def __init__(self, screen, access):
        self.screen = screen
        self.access = access

    def run(self):
        try:
            state = StateReading(self.access).read()
        except LibvirtCallFailed as error:
            self.screen.say(f"libvirt cannot be read: {error}")
            return
        try:
            self.access.copy_folder.make()
        except FileFailed as error:
            self.screen.say(f"nothing copied: {error}")
            return
        lines = []
        with self.screen.app.suspend():
            print("state-copy runs (sudo may ask your password) ...", flush=True)
            for vm in state.vms:
                if not vm.nix:
                    lines.append(self._copy(vm))
        self.screen.say("\n".join(lines) or "no VM to copy")

    def _copy(self, vm):
        if vm.active:
            return f"{vm.name}, runs, shut it down first"
        uuid = vm.root.findtext("uuid")
        folder = self.access.copy_folder
        where = folder.state_folder(vm.name)
        try:
            self.access.privileged_steps.run_captured("state-copy", ["save", vm.name, uuid])
        except StepFailed as failure:
            output = failure.answer.output
            return f"{vm.name}, not copied: {output.splitlines()[-1] if output else failure.code}"
        if folder.has_tpm_state(vm.name, uuid):
            return f"{vm.name}, firmware variables and TPM state copied into {where}"
        return f"{vm.name}, firmware variables copied, no TPM state"

    screen = None
    access = None
