from model.CacheBank import CacheBank
from model.CpuSet import CpuSet
from model.Gigabytes import Gigabytes
from model.Host import Host
from model.SystemFailures import SystemFailures
from model.enums import ThreadKind


class HostReading:
    """The host's figures read from libvirt's capabilities and from the disk of the images."""

    def __init__(self, libvirt, files, images_folder):
        self.libvirt = libvirt
        self.files = files
        self.images_folder = images_folder

    def read(self):
        with self.kFailures.raised_as_model():
            return self._read()

    def _read(self):
        host = Host()
        capabilities = self.libvirt.capabilities()
        siblings = self._siblings(capabilities)
        host.ram = self.libvirt.host_memory()
        host.threads = len(siblings) or self.libvirt.host_cpu_count()
        host.sibling_groups = sorted({tuple(sorted(group)) for group in siblings.values()})
        host.kinds = self._kinds(host.sibling_groups, self._banks(capabilities))
        host.threads_per_core = max((len(group) for group in host.sibling_groups), default=1)
        host.free = self.files.free_bytes(self.images_folder)
        return host

    def _siblings(self, capabilities):
        siblings = {}
        for cpu in capabilities.findall("./host/topology/cells/cell/cpus/cpu"):
            siblings[int(cpu.get("id"))] = CpuSet.parse(cpu.get("siblings") or cpu.get("id"))
        return siblings

    def _banks(self, capabilities):
        banks = []
        for element in capabilities.findall("./host/cache/bank"):
            if element.get("level") != "3":
                continue
            bank = CacheBank()
            bank.threads = CpuSet.parse(element.get("cpus"))
            if bank.threads:
                size = int(element.get("size")) * Gigabytes.kUnitBytes.get(element.get("unit"), 1)
                bank.bytes_per_thread = size / len(bank.threads)
                banks.append(bank)
        return banks

    def _kinds(self, groups, banks):
        # The fast kind is the bank with the most cache per thread; the others
        # are dense.
        best = max((bank.bytes_per_thread for bank in banks), default=0)
        kinds = {thread: ThreadKind.kDense.value for group in groups for thread in group}
        for bank in banks:
            kind = ThreadKind.kFast if bank.bytes_per_thread == best else ThreadKind.kDense
            for thread in bank.threads:
                kinds[thread] = kind.value
        return kinds

    libvirt = None
    files = None
    images_folder = ""
    kFailures = SystemFailures()
