from model.StateVms import StateVms


class BrokerLines:
    """The broker section's words: its VMs, a VM's line with its list of destinations, and a destination's name."""

    def __init__(self, state, configuration):
        self.state = state
        self.configuration = configuration

    def vms(self):
        """Every VM the tool owns (each VM of libvirt's store that Nix does not define), templates left out, by name."""
        return [vm for vm in self.state.vms if not vm.nix and not vm.template]

    def name(self, name):
        """A name of a list of destinations: the host's station name as it is, a name with no VM defined now with the settings' mark after it."""
        if name == self.configuration.host_port or StateVms(self.state).has(name):
            return name
        return f"{name} ({self.configuration.exchange.retired_mark})"

    def line(self, vm):
        """A VM's line: its state and its list of destinations, the settings' word for an empty list or no station."""
        exchange = self.configuration.exchange
        names = vm.station.destinations if vm.has_station else []
        listed = ", ".join(self.name(name) for name in names) or exchange.nothing_listed
        return f"{vm.name}: {'running' if vm.active else 'off'}, {exchange.sends_to_label}: {listed}"

    state = None
    configuration = None
