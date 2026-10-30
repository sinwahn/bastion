import re

from model.Gigabytes import Gigabytes


class Refusals:
    """The reasons a start, a new VM's name or a new network's name is refused."""

    def __init__(self, configuration):
        self.configuration = configuration

    def of_start(self, host, running, vm):
        """The reasons vm may not start now; an empty list lets it start."""
        # Each VM is offered at most what the host has less its share and less
        # the service VMs; a start is refused while the running VMs together
        # would pass the host.
        others = [other for other in running if other.name != vm.name]
        return self._thread_refusals(host, others, vm) + self._memory_refusals(host, others, vm)

    def of_vm_name(self, name, used, retired):
        """The reason a new VM's name is refused; empty when it is not."""
        # The name is also its cable's name on the switch. used: the names of
        # libvirt's VMs and the names in use on the host; an entry in the live
        # data file with no VM behind it does not refuse its name. A
        # template's name is refused since a template's definition takes the
        # entry of its name at Windows Setup.
        templates = {template.name for template in self.configuration.templates}
        if not re.fullmatch(r"[A-Za-z0-9-]+", name):
            return "letters, digits and dashes only."
        if len(name) > self.configuration.name_maximum:
            return f"at most {self.configuration.name_maximum} characters: the name is also the VM's cable."
        for prefix in self.configuration.refused_prefixes:
            if name.startswith(prefix):
                return f"a name starting with {prefix} is libvirt's own for cables."
        if name in used:
            return f"{name} is already used."
        if name in retired:
            return f"a retired VM has this name; its disk and definition are kept in retired/{name}."
        if name in templates:
            return f"{name} is a template's name; the template takes its entry in networks.json at Windows Setup."
        return self.kNoRefusal

    def of_network_name(self, name, networks):
        """The reason a new network's name is refused; empty when it is not."""
        # The name is also firewall-vm's leg on that network, so it may not be
        # a name of host-networks.nix (its switches, VMs and cables) nor the
        # loopback inside firewall-vm.
        firewall = self.configuration.firewall_vm
        if not re.fullmatch(r"[A-Za-z0-9-]+", name):
            return "letters, digits and dashes only."
        if len(name) > self.configuration.name_maximum:
            return f"at most {self.configuration.name_maximum} characters: the name is also {firewall}'s leg."
        if name in networks:
            return f"{name} is already a network."
        if name in self.configuration.host_network_names:
            return f"{name} is a name of host-networks.nix (a switch, a service VM or a cable)."
        if name == self.kLoopback:
            return f"{name} is {firewall}'s loopback."
        return self.kNoRefusal

    def _thread_refusals(self, host, others, vm):
        share = self.configuration.host_share
        services = self.configuration.service_vms
        free = host.threads - share.threads - sum(other.vcpus for other in others) - sum(service.threads for service in services)
        if vm.vcpus <= free:
            return []
        who = ", ".join([f'{service.name} {service.threads}' for service in services]
                        + [f'{other.name} {other.vcpus}' for other in others])
        return [f'{vm.name} needs {vm.vcpus} threads and {max(free, 0)} are free: '
                f'the host has {host.threads}, {share.threads} stay for the host, '
                f'running now: {who}.']

    def _memory_refusals(self, host, others, vm):
        share = self.configuration.host_share
        services = self.configuration.service_vms
        held = sum(other.memory for other in others) + sum(service.memory for service in services)
        free = host.ram - share.ram * Gigabytes.kMibPerGib - held
        if vm.memory <= free:
            return []
        gigabytes = Gigabytes.of_mebibytes
        who = ", ".join([f'{service.name} {gigabytes(service.memory)}' for service in services]
                        + [f'{other.name} {gigabytes(other.memory)}' for other in others])
        return [f'{vm.name} needs {gigabytes(vm.memory)} GB of RAM and {gigabytes(max(free, 0))} GB are free: '
                f'the host has {gigabytes(host.ram)}, {share.ram} stay for the host, '
                f'running now (GB): {who}.']

    configuration = None
    kNoRefusal = ""
    # The loopback inside every Linux system, firewall-vm's too: the kernel
    # gives it this fixed name (drivers/net/loopback.c).
    kLoopback = "lo"
