from model.StationEntry import StationEntry
from model.enums import InternetRule


class StationEdit:
    """Changes to a station's entry, each key kept where the file holds it and a new key added at its end."""

    def __init__(self, destinations_key):
        self.destinations_key = destinations_key

    def made(self, network, ip, mac):
        entry = StationEntry()
        self.set_network(entry, network)
        self.set_ip(entry, ip)
        self.set_mac(entry, mac)
        return entry

    def set_network(self, entry, network):
        entry.network = network
        self._keep(entry, "network")

    def set_ip(self, entry, ip):
        entry.ip = ip
        self._keep(entry, "ip")

    def set_mac(self, entry, mac):
        entry.mac = mac
        self._keep(entry, "mac")

    def set_rule(self, entry, rule, names):
        """The internet rule, and for listed its names; any other rule drops the names."""
        entry.rule = rule
        self._keep(entry, "rule")
        if rule == InternetRule.kListed.value:
            entry.names = names
            self._keep(entry, "names")
        else:
            self._drop(entry, "names")

    def set_resolution(self, entry, size):
        entry.resolution = size
        self._keep(entry, "resolution")

    def drop_resolution(self, entry):
        self._drop(entry, "resolution")

    def set_destinations(self, entry, names):
        entry.destinations = names
        self._keep(entry, self.destinations_key)

    def drop_destinations(self, entry):
        self._drop(entry, self.destinations_key)

    def _keep(self, entry, key):
        if key not in entry.keys:
            entry.keys.append(key)

    def _drop(self, entry, key):
        if key in entry.keys:
            entry.keys.remove(key)

    destinations_key = ""
