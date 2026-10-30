from model.Gigabytes import Gigabytes
from model.HostThreads import HostThreads
from model.StateVms import StateVms
from model.enums import InternetRule


class VmLines:
    """A VM's words on the screens: its graphics, its internet rule, its row in the VMs table, its details and a saved change."""

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

    def details(self, vm):
        """The VM screen's lines: its state, cores, RAM, disk, graphics, network and internet rule."""
        lines = [f"{vm.name}: {'running' if vm.active else 'off'}",
                 f"cores: {vm.vcpus} threads; {self._kinds(vm)}",
                 f"RAM: {Gigabytes.of_mebibytes(vm.memory)} GB", f"disk: {vm.capacity // Gigabytes.kGib} GB",
                 f"graphics: {self.graphics(vm)}",
                 f"network: {vm.station.network if vm.has_station else '-'}; internet rule: {self.rule(vm)}"
                 + (f"; address {vm.station.ip}" if vm.has_station else "")]
        if vm.nix:
            lines.append("defined by Nix, which rewrites it at every boot")
        return "\n".join(lines)

    def saved(self, vm, what):
        return f"saved: {what}" + ("; takes effect at its next start" if vm.active else "")

    def _kinds(self, vm):
        threads = HostThreads(self.state.host)
        if vm.active:
            return threads.kinds_text(vm.live_pins)
        return f"{threads.preference_of(vm.pins).word()} cores first"

    state = None
