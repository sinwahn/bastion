import xml.etree.ElementTree as ET


class CableEdit:
    """A VM's cable on the switch: its link, its network as a vlan tag and its port."""

    def __init__(self, switch):
        self.switch = switch

    def link_down(self, root):
        """The cable starts with its link down."""
        for interface in self._cables(root):
            for old in interface.findall("link"):
                interface.remove(old)
            interface.append(ET.fromstring("<link state='down'/>"))

    def set_lane(self, root, content, network):
        """The cable put on network: its vlan tag, none for the switch's own network; its port isolated unless the network's reach-each-other is true."""
        entry = content.networks[network]
        for interface in self._cables(root):
            for old in interface.findall("vlan") + interface.findall("port"):
                interface.remove(old)
            if network != self.switch:
                interface.append(ET.fromstring(f"<vlan><tag id='{entry.vlan_tag}'/></vlan>"))
            interface.append(ET.fromstring(f"<port isolated='{'no' if entry.reach_each_other else 'yes'}'/>"))

    def network_of(self, root, content):
        """The network whose vlan tag the cable holds, the switch's own without one; empty for a tag of no network or no cable."""
        for interface in self._cables(root):
            tag = interface.find("./vlan/tag")
            if tag is None:
                return self.switch
            for name, entry in content.networks.items():
                if str(entry.vlan_tag) == tag.get("id"):
                    return name
            return self.kNoNetwork
        return self.kNoNetwork

    def _cables(self, root):
        interfaces = []
        for interface in root.findall("./devices/interface"):
            source = interface.find("source")
            if source is not None and source.get("bridge") == self.switch:
                interfaces.append(interface)
        return interfaces

    switch = ""
    kNoNetwork = ""
