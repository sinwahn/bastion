from model.Gigabytes import Gigabytes


class Offers:
    """The cores, RAM and disk sizes a VM may be given; every VM's full disk size counts as taken."""

    def __init__(self, configuration):
        self.configuration = configuration

    def thread_counts(self, host):
        """The thread counts a VM may be given, in whole cores."""
        top = host.threads - self.configuration.host_share.threads - sum(
            service.threads for service in self.configuration.service_vms)
        return list(range(host.threads_per_core, top + 1, host.threads_per_core))

    def ram_sizes(self, host):
        """The RAM sizes a VM may be given, in GiB, in steps."""
        step = self.configuration.pick_steps.ram
        top = host.ram - self.configuration.host_share.ram * Gigabytes.kMibPerGib - sum(
            service.memory for service in self.configuration.service_vms)
        return list(range(step, top // Gigabytes.kMibPerGib + 1, step))

    def promised(self, vms):
        """What every VM's disk may still grow by, in bytes."""
        return sum(max(vm.capacity - vm.allocation, 0) for vm in vms)

    def disk_room(self, host, vms):
        """The bytes still free for VM disks: the host's free space, less the host's share, less what every VM's disk may still grow by."""
        return host.free - self.configuration.host_share.disk * Gigabytes.kGib - self.promised(vms)

    def new_disk_sizes(self, start, room):
        """The sizes (GiB) of a new disk, from the template's size in steps, each counted whole."""
        sizes = []
        size = start
        while size * Gigabytes.kGib <= room:
            sizes.append(size)
            size += self.configuration.pick_steps.disk
        return sizes

    def growth_sizes(self, current, room):
        """The bigger sizes (GiB) of a disk now current; what it grows by must fit the room, its own promise counted there."""
        sizes = []
        size = current + self.configuration.pick_steps.disk
        while (size - current) * Gigabytes.kGib <= room:
            sizes.append(size)
            size += self.configuration.pick_steps.disk
        return sizes

    configuration = None
