from model.Gigabytes import Gigabytes
from model.HostThreads import HostThreads
from model.Offers import Offers
from model.StateReading import StateReading
from model.StateVms import StateVms
from model.enums import ThreadKind
from system.errors import LibvirtCallFailed, ShellCommandFailed
from user.ServiceLines import ServiceLines
from user.UplinkStatus import UplinkStatus


class StatusReport:
    """The status screen's text: the first thing wrong on top, then the VMs, the host, the networks, the service VMs, the uplinks and the internet."""

    def __init__(self, access):
        self.access = access

    def text(self):
        wrong = []
        lines = []
        try:
            self._add_state(StateReading(self.access).read(), lines, wrong)
        except LibvirtCallFailed as error:
            wrong.append(f"libvirt cannot be read ({error}): no VM can be shown or started. "
                         "Do: sudo systemctl start libvirtd")
        self._add_services(lines, wrong)
        self._add_uplinks(lines, wrong)
        self._add_internet(lines, wrong)
        head = ["WRONG: " + wrong[0], ""] if wrong else ["Nothing is wrong.", ""]
        exchange = self.access.configuration.exchange
        return "\n".join(head + lines + ["", "v: the VMs, n: the networks, d: the devices, l: looking-glass, "
                                         f"{exchange.section_key}: {exchange.section}, r: read again, q: quit"])

    def _add_state(self, state, lines, wrong):
        templates = self.access.templates
        names = [vm.name for vm in state.vms if not vm.template]
        sealed = ", ".join(f"{template.word} {'sealed' if templates.is_sealed(template) else 'not sealed'}"
                           for template in self.access.configuration.templates)
        running = ", ".join(vm.name for vm in StateVms(state).running()) or "none"
        lines.append(f"VMs: {len(names)}, templates: {sealed}; running: {running}")
        for vm in state.vms:
            if vm.nix:
                lines.append(f"{vm.name}: defined by Nix, which rewrites it at every boot")
        lines.append(self._host_line(state))
        self._add_networks(state, lines, wrong)

    def _host_line(self, state):
        host = state.host
        threads = HostThreads(host)
        room = Offers(self.access.configuration).disk_room(host, state.vms)
        return (f"host: {host.threads} threads ({threads.count(ThreadKind.kFast)} fast, {threads.count(ThreadKind.kDense)} dense), "
                f"{Gigabytes.of_mebibytes(host.ram)} GB RAM, {host.free // Gigabytes.kGib} GB free on the disk, "
                f"{max(room, 0) // Gigabytes.kGib} GB of it free for VM disks")

    def _add_networks(self, state, lines, wrong):
        failure = state.failure
        if failure.failed and failure.refused:
            wrong.append(f"networks.json cannot be read ({failure.reason}): new VMs get no address "
                         "and no internet rule can change")
        elif failure.failed:
            wrong.append(f"networks.json cannot be read ({failure.reason}): new VMs get no address "
                         "and no internet rule can change. Do: sudo systemctl restart networks-apply")
        else:
            stations = state.content.stations.values()
            networks = ", ".join(f"{name} ({sum(1 for station in stations if station.network == name)} VMs)"
                                 for name in state.content.networks)
            lines.append(f"networks: {networks}")

    def _add_services(self, lines, wrong):
        for service in self.access.configuration.service_vms:
            up = self.access.service_units.is_active(service.unit)
            lines.append(f"{service.name}: {'running' if up else 'not running'}")
            if not up:
                wrong.append(ServiceLines().wrong(service))

    def _add_uplinks(self, lines, wrong):
        try:
            lines.extend(UplinkStatus(self.access).lines())
        except ShellCommandFailed:
            lines.append("uplinks: run gate status")
            wrong.append("uplinks cannot be read here: run gate status")

    def _add_internet(self, lines, wrong):
        answers = self.access.internet.answers()
        lines.append(f"internet: {'yes' if answers else 'no'}")
        if not answers:
            wrong.append("internet: no: the host reaches nothing outside. Do: gate status")

    access = None
