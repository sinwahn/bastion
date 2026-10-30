from system.WifiCheck import WifiFacts
from system.errors import ShellCommandFailed


class UplinkStatus:
    """The host's uplinks as gate status reads them, without sudo, each cable's route among them."""

    # An uplink whose way out is decided inside wifi-vm (a rerouted cable, and
    # the Wi-Fi while a cable is rerouted) is read from wifi-check there, and
    # so is the way out of the host's route through the VMs. A cable's route
    # is "vm" (rerouted through firewall-vm, its card wifi-vm's) while its
    # host profile does not connect by itself, "ethernet" (direct to the
    # host) while it does; its kind in uplinks.nix while the profile is not
    # made.

    def __init__(self, access):
        self.access = access
        self.configuration = access.configuration

    def lines(self):
        """The lines; ShellCommandFailed when NetworkManager refuses the read."""
        active = self.access.uplink_profiles.active_names()
        uplinks = self.configuration.uplinks
        routes = {uplink.name: self.route(uplink) for uplink in uplinks if uplink.is_cable}
        rerouted = [name for name, route in routes.items() if route == "vm"]
        inside = set(rerouted) | ({uplink.name for uplink in uplinks if uplink.is_path} if rerouted else set())
        facts = self.access.wifi_check.read(self.configuration.internet_seconds) if rerouted else WifiFacts()
        preferred = self._preferred(rerouted, inside, facts)
        lines = [self._uplink_line(uplink, inside, facts, active, preferred) for uplink in uplinks]
        lines += [self._route_line(uplink, routes[uplink.name]) for uplink in uplinks if uplink.is_cable]
        lines.append(f"the host's route: {self._host_route(rerouted, facts)}")
        return lines

    def route(self, uplink):
        """A cable's route now, as gate reads it."""
        try:
            autoconnect = self.access.uplink_profiles.autoconnect(uplink.name)
        except ShellCommandFailed:
            return uplink.kind
        return {"yes": "ethernet", "no": "vm"}.get(autoconnect, uplink.kind)

    def _preferred(self, rerouted, inside, facts):
        lowest = 0
        found = False
        preferred = self.configuration.preferred_uplink
        for uplink in self.configuration.uplinks:
            if uplink.name in rerouted:
                continue
            metric = self.access.uplink_profiles.route_metric(uplink.name)
            if metric.lstrip("-").isdigit() and (not found or int(metric) < lowest):
                lowest = int(metric)
                found = True
                preferred = uplink.name
        if preferred in inside:
            metrics = sorted((int(fact.metric), name) for name, fact in facts.uplinks.items() if fact.metric.lstrip("-").isdigit())
            if metrics:
                preferred = metrics[0][1]
        return preferred

    def _uplink_line(self, uplink, inside, facts, active, preferred):
        name = uplink.name
        if name in inside:
            if name not in facts.uplinks:
                return f"{name}: cannot be read: {self.configuration.wifi_vm} does not answer"
            fact = facts.uplinks[name]
            up = "up" if fact.state == "up" else "not up"
            allowed = "allowed" if fact.permission == "allowed" else "not allowed"
        else:
            allowed = "allowed" if self.access.uplink_profiles.never_default(name) == "no" else "not allowed"
            up = "up" if name in active else "not up"
        return f"{name}: {up}, {allowed}" + (", preferred" if name == preferred else "")

    def _route_line(self, uplink, route):
        """The sentence of a cable's route (host-networks.nix)."""
        reroute = self.configuration.reroute
        sentence = reroute.through if route == "vm" else reroute.direct
        return sentence.format(cable=uplink.name, firewall=self.configuration.firewall_vm)

    def _host_route(self, rerouted, facts):
        device = self.access.kernel_routes.default_device()
        names = {uplink.device: uplink.name for uplink in self.configuration.uplinks}
        paths = {uplink.device for uplink in self.configuration.uplinks if uplink.is_path}
        firewall = self.configuration.firewall_vm
        if not device:
            return "none"
        if device in paths and rerouted and facts.route:
            if facts.route[0] == "none":
                return "none"
            if facts.route[0] == "other":
                return f"through {firewall}, out over {' '.join(facts.route[1:])}, not an uplink of uplinks.nix"
            return f"{facts.route[0]}, through {firewall}"
        if device in names:
            return names[device]
        return f"{device}, not an uplink of uplinks.nix"

    access = None
    configuration = None
