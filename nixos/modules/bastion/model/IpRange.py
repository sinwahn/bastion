import ipaddress


class IpRange:
    """A network's IPv4 range."""

    def __init__(self, text):
        self.text = text

    def first(self):
        """The first address of the range: firewall-vm's on that network."""
        return str(next(self._network().hosts()))

    def next_free(self, taken):
        """The first address of the range not in taken; empty when every one is taken."""
        for candidate in self._network().hosts():
            if str(candidate) not in taken:
                return str(candidate)
        return self.kNoneFree

    def third_octet(self):
        return self._network().network_address.packed[2]

    def first_two_octets(self):
        return self._network().network_address.packed[:2]

    def _network(self):
        return ipaddress.ip_network(self.text, strict=False)

    text = ""
    kNoneFree = ""
