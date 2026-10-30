from system.enums import WaitSeconds
from system.errors import ShellCommandFailed


class SwitchPorts:
    """The host's links and the vlans of the switches' ports, read with ip and bridge as the user."""

    def __init__(self, shell, ip, bridge):
        self.shell = shell
        self.ip = ip
        self.bridge = bridge

    def read(self):
        self.links = {link.get("ifname"): link for link in self._listing(self.ip, "-j", "link", "show")}
        self.vlans = {port.get("ifname"): port.get("vlans", []) for port in self._listing(self.bridge, "-j", "vlan", "show")}

    def master(self, port):
        return self.links.get(port, {}).get("master")

    def untagged_vlan(self, port):
        return next((entry.get("vlan") for entry in self.vlans.get(port, []) if self._is_untagged(entry)), 0)

    def carries(self, port, vlan):
        return any(entry.get("vlan") == vlan for entry in self.vlans.get(port, []))

    def carries_untagged(self, port, vlan):
        return any(entry.get("vlan") == vlan and self._is_untagged(entry) for entry in self.vlans.get(port, []))

    def _is_untagged(self, entry):
        return self.kUntagged <= set(entry.get("flags", []))

    def _listing(self, *command):
        try:
            return self.shell.read_json(list(command), WaitSeconds.kCommand)
        except ShellCommandFailed:
            return []

    shell = None
    ip = ""
    bridge = ""
    links = {}
    vlans = {}
    kUntagged = {"PVID", "Egress Untagged"}
