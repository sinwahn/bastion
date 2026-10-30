from model.CableEdit import CableEdit
from model.StateReading import StateReading
from model.StateVms import StateVms
from user.PathPieces import PathPieces
from user.PathServicePieces import PathServicePieces


class PathCheck:
    """The path check of a station: one line per piece in the order its traffic goes, the first no on top in gate status's form, then its last refused tries."""

    # All read as the user: libvirt; ip and bridge for the cables; systemctl
    # for the service VMs; over vsock with socat the two answer points inside
    # them (bastion.nix's firewallCheck and wifiCheck). wifi-check is waited
    # for internet-wait seconds; firewall-check twice that, since its own
    # request to the internet target may take internet-wait by itself; what
    # an answer point printed before its wait ran out is kept, a fact it did
    # not print cannot be read.

    def __init__(self, access, name):
        self.access = access
        self.name = name
        self.configuration = access.configuration

    def read(self):
        self.state = StateReading(self.access).read()
        self.network = self.state.content.stations[self.name].network
        self.vlan_tag = self.state.content.networks[self.network].vlan_tag
        self.ports = self.access.switch_ports
        self.ports.read()
        self.pieces = PathPieces()
        services = PathServicePieces(self.access, self.pieces)
        self._add_cable()
        self._add_firewall_cables()
        services.add_service(self.configuration.firewall_vm)
        facts = self.access.firewall_check.read(self.name, 2 * self.configuration.internet_seconds)
        services.add_leg(self.name, self.network, facts)
        self._add_other_cables()
        services.add_service(self.configuration.wifi_vm)
        services.add_wifi()
        services.add_internet(facts)
        self.tries = self._tries(facts)

    def text(self):
        return self.pieces.text(self.tries)

    def _add_cable(self):
        # The VM's cable: on the switch with its network's vlan tag untagged,
        # against its station's network.
        name, network, switch = self.name, self.network, self.configuration.switch
        subject = f"{name}'s cable"
        vms = StateVms(self.state)
        if not vms.has(name):
            self.pieces.add(subject, "not in libvirt's store",
                            f"{subject}: not in libvirt's store: {name} has no VM, so it has no cable.")
            return
        vm = vms.vm(name)
        move = self._move(vm)
        again = f"Do: shut {name} down and start it again"
        if not vm.active:
            self.pieces.add(subject, "off" + move, f"{subject}: off: {name} is off, so it has no cable. "
                                                   f"Do: start {name} in the VMs section")
        elif self.ports.master(name) != switch:
            fact = f"running, not on {switch}" + move
            self.pieces.add(subject, fact, f"{subject}: {fact}. {again}")
        elif self.ports.untagged_vlan(name) == self.vlan_tag:
            self.pieces.add_yes(subject, f"running, on {switch}, on its network {network}" + move)
        else:
            fact = f"running, on {switch}, on {self._network_on(self.ports.untagged_vlan(name))}, its network is {network}" + move
            self.pieces.add(subject, fact, f"{subject}: {fact}. {again}")

    def _move(self, vm):
        target = CableEdit(self.configuration.switch).network_of(vm.root, self.state.content)
        if target and target != self.network:
            return f", moves to {target} at its next start"
        return ""

    def _network_on(self, vlan):
        return next((name for name, entry in self.state.content.networks.items() if entry.vlan_tag == vlan), "no network")

    def _add_firewall_cables(self):
        # firewall-vm's cable on the switch carries the VM's network: its vlan
        # tag untagged for the switch's own network, else tagged.
        switch, network, vlan = self.configuration.switch, self.network, self.vlan_tag
        for cable in self.configuration.cables:
            if cable.switch != switch:
                continue
            subject = f"{self.configuration.firewall_vm}'s cable on {switch}"
            if self.ports.master(cable.name) != switch:
                fact = f"not on {switch}"
            elif not self.ports.carries(cable.name, vlan) or (network == switch and not self.ports.carries_untagged(cable.name, vlan)):
                fact = f"does not carry {network}"
            else:
                fact = ""
            self.pieces.add(subject, fact or f"carries {network}", fact and f"{subject}: {fact}. {self.kApplyAgain}")

    def _add_other_cables(self):
        others = {}
        for cable in self.configuration.cables:
            if cable.switch != self.configuration.switch:
                others.setdefault(cable.switch, []).append(cable.name)
        for switch, names in others.items():
            subject = " and ".join(names)
            missing = [name for name in names if self.ports.master(name) != switch]
            fact = f"not on {switch}: {', '.join(missing)}" if missing else ""
            self.pieces.add(subject, fact or f"on {switch}", fact and f"{subject}: {fact}. {self.kApplyAgain}")

    def _tries(self, facts):
        # The VM's last refused tries (firewall-check).
        name, firewall = self.name, self.configuration.firewall_vm
        if not facts.has_line and not facts.station_unknown:
            return [f"{name}'s last refused tries: cannot be read: {firewall} does not answer"]
        if facts.tries:
            return [f"{name}'s last refused tries:"] + [", ".join(tried) for tried in facts.tries]
        return [f"{name}'s last refused tries: none in {firewall}'s journal"]

    access = None
    name = ""
    configuration = None
    state = None
    network = ""
    vlan_tag = 0
    ports = None
    pieces = None
    tries = ()
    kApplyAgain = "Do: sudo systemctl restart networks-apply.service"
