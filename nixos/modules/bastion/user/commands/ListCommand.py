from model.Gigabytes import Gigabytes
from model.StateReading import StateReading
from model.StateVms import StateVms
from user.enums import ExitCode


class ListCommand:
    """bastion list: every VM that is not a template, its state in virsh's words, its disk's size in GiB and the card it holds by libvirt's name for the device; then each template, sealed, its state, or no image yet."""

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return arguments == [self.kWord]

    def run(self, arguments):
        state = StateReading(self.access).read()
        vms = StateVms(state)
        for vm in state.vms:
            if vm.template:
                continue
            cards = [device.name for device in vms.given_card(vm)]
            print(", ".join([vm.name, state.libvirt.state_word(vm.name) or "not made",
                             f"{vm.capacity // Gigabytes.kGib} GiB"] + cards))
        for template in self.access.configuration.templates:
            print(f"{template.name}, {self._template_state(state, template)}")

    def exit_code(self):
        return ExitCode.kDone

    def _template_state(self, state, template):
        if self.access.templates.is_sealed(template):
            return "sealed"
        return state.libvirt.state_word(template.name) or "no image yet"

    access = None
    kWord = "list"
