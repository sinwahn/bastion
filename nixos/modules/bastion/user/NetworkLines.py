from model.CableEdit import CableEdit
from model.StateVms import StateVms
from user.VmLines import VmLines


class NetworkLines:
    """The networks section's words: a network's entry and a station's line."""

    def __init__(self, state, configuration):
        self.state = state
        self.configuration = configuration

    def network(self, name, count):
        """A network's entry: its range, its count of VMs and whether they reach each other."""
        entry = self.state.content.networks[name]
        return (f"{name}: {entry.ip_range}, {count} VMs\n"
                f"VMs reach each other: {'yes' if entry.reach_each_other else 'no'}")

    def station(self, name):
        """A station's line: its state, internet rule and IP, and the network its definition puts it on at its next start when that is another one."""
        station = self.state.content.stations[name]
        vms = StateVms(self.state)
        if not vms.has(name):
            return f"{name}: not in libvirt's store, internet {station.rule}, address {station.ip}"
        vm = vms.vm(name)
        line = f"{name}: {'running' if vm.active else 'off'}, internet {VmLines(self.state).rule(vm)}, address {station.ip}"
        target = CableEdit(self.configuration.switch).network_of(vm.root, self.state.content)
        if target and target != station.network:
            line += f", moves to {target} at its next start"
        return line

    state = None
    configuration = None
