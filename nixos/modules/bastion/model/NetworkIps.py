from model.IpRange import IpRange
from model.NetworkEntry import NetworkEntry


class NetworkIps:
    """A station's next free IP, a new network's vlan tag and its range."""

    def __init__(self, configuration):
        self.configuration = configuration

    def free_ip(self, content, network):
        """The next free IP of network's range: never the range's first (firewall-vm's on that network), the host's, or a station's."""
        ip_range = IpRange(content.networks[network].ip_range)
        taken = {station.ip for station in content.stations.values()} | {ip_range.first(), self.configuration.host_ip}
        return ip_range.next_free(taken)

    def next_lane(self, content):
        """A new network's vlan tag: one above the highest among the networks."""
        return max(network.vlan_tag for network in content.networks.values()) + 1

    def next_range(self, content):
        """A new network's range: the /24 above the highest third octet, in the same /16 as the switch's network."""
        top = max(IpRange(network.ip_range).third_octet() for network in content.networks.values())
        first, second = IpRange(content.networks[self.configuration.switch].ip_range).first_two_octets()
        return f"{first}.{second}.{top + 1}.0/24"

    def made(self, content, ip_range):
        """A new network's entry, its VMs kept apart."""
        entry = NetworkEntry()
        entry.vlan_tag = self.next_lane(content)
        entry.ip_range = ip_range
        entry.reach_each_other = False
        entry.keys = ["lane", "ip-range", "reach-each-other"]
        return entry

    configuration = None
