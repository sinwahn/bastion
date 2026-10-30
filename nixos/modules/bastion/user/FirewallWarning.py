class FirewallWarning:
    """The line a start shows while firewall-vm does not run."""

    def __init__(self, access):
        self.access = access

    def lines(self):
        """The line; none while firewall-vm runs."""
        configuration = self.access.configuration
        firewall = configuration.firewall_vm
        unit = next(service.unit for service in configuration.service_vms if service.name == firewall)
        if self.access.service_units.is_active(unit):
            return []
        return [f"No internet for now: {firewall} does not run (gate status)."]

    access = None
