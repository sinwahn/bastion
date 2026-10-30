from model.Gigabytes import Gigabytes
from model.StateVms import StateVms
from model.enums import InternetRule


class VmLines:
    """A VM's words on the screens: its graphics, its internet rule, its row in the VMs table and a saved change."""

    def __init__(self, state):
        self.state = state

    def graphics(self, vm):
        for device in StateVms(self.state).given_card(vm):
            return f"emulated + {device.name}"
        return "emulated"

    def rule(self, vm):
        if not vm.has_station:
            return "-"
        if vm.station.rule == InternetRule.kListed.value:
            return f"listed ({len(vm.station.names)} names)"
        return vm.station.rule

    def row(self, vm):
        return [vm.name, "running" if vm.active else "off", str(vm.vcpus),
                Gigabytes.of_mebibytes(vm.memory) + " GB", str(vm.capacity // Gigabytes.kGib) + " GB",
                self.graphics(vm), vm.station.network if vm.has_station else "-", self.rule(vm)]

    def saved(self, vm, what):
        return f"saved: {what}" + ("; takes effect at its next start" if vm.active else "")

    state = None
