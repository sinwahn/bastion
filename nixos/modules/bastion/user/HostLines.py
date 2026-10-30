from model.Gigabytes import Gigabytes
from model.Offers import Offers
from model.PciFunctions import PciFunctions
from model.StateVms import StateVms


class HostLines:
    """The host's words on the screens: what is held, the disk's room and each graphics device."""

    def __init__(self, state, configuration):
        self.state = state
        self.configuration = configuration

    def holding(self):
        """The line above the cores and RAM screens."""
        gigabytes = Gigabytes.of_mebibytes
        host = self.state.host
        services = ", ".join(f"{service.name} {service.threads} and {gigabytes(service.memory)} GB"
                             for service in self.configuration.service_vms)
        running = ", ".join(f"{vm.name} holds {vm.vcpus} and {gigabytes(vm.memory)} GB"
                            for vm in StateVms(self.state).running()) or "no VM"
        share = self.configuration.host_share
        return (f"the host has {host.threads} threads and {gigabytes(host.ram)} GB of RAM; "
                f"{share.threads} threads and {share.ram} GB stay for the host; "
                f"the service VMs: {services}; running now: {running}")

    def disk(self):
        offers = Offers(self.configuration)
        promised = offers.promised(self.state.vms)
        room = offers.disk_room(self.state.host, self.state.vms)
        return (f"{max(room, 0) // Gigabytes.kGib} GB of the disk are free for VM disks: {self.state.host.free // Gigabytes.kGib} GB are free, "
                f"{self.configuration.host_share.disk} GB stay for the host, {promised // Gigabytes.kGib} GB are promised to VM disks that may still grow")

    def device(self, device):
        where = f"{PciFunctions().text(device.function)}, driver {device.driver or 'none'}"
        if device.passthrough:
            who = ", ".join(device.holders) if device.holders else "no VM"
            return f"{device.name} ({where}): one VM at a time; held now by {who}"
        return f"{device.name} ({where}): the host's; no VM uses it; Linux VMs come later"

    state = None
    configuration = None
