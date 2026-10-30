import contextlib
import xml.etree.ElementTree as ET

import libvirt

from system.DiskSizes import DiskSizes
from system.errors import LibvirtCallFailed


class LibvirtConnection:
    """Every call into libvirt's store at the settings' uri."""

    def __init__(self, uri, log):
        self.uri = uri
        self.log = log

    def open(self):
        with self._calls():
            self.connection = libvirt.open(self.uri)

    def domain_names(self):
        with self._calls():
            return [domain.name() for domain in self.connection.listAllDomains(0)]

    def definition_text(self, name):
        with self._calls():
            return self.connection.lookupByName(name).XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)

    def definition(self, name):
        return ET.fromstring(self.definition_text(name))

    def live_definition(self, name):
        with self._calls():
            return ET.fromstring(self.connection.lookupByName(name).XMLDesc(0))

    def is_active(self, name):
        with self._calls():
            return bool(self.connection.lookupByName(name).isActive())

    def disk_sizes(self, name, target):
        with self._calls():
            figures = self.connection.lookupByName(name).blockInfo(target)
        sizes = DiskSizes()
        sizes.capacity = figures[0]
        sizes.allocation = figures[1]
        return sizes

    def define(self, text):
        with self._calls():
            self.connection.defineXMLFlags(text, libvirt.VIR_DOMAIN_DEFINE_VALIDATE)

    def create(self, name):
        with self._calls():
            self.connection.lookupByName(name).create()

    def shut_down(self, name):
        with self._calls():
            self.connection.lookupByName(name).shutdown()

    def undefine_keeping_state(self, name):
        with self._calls():
            self.connection.lookupByName(name).undefineFlags(
                libvirt.VIR_DOMAIN_UNDEFINE_KEEP_NVRAM | libvirt.VIR_DOMAIN_UNDEFINE_KEEP_TPM)

    def state_word(self, name):
        """The VM's state in virsh's words, as virsh domstate prints it; empty when libvirt has no VM of that name."""
        # libvirt-python 12.2.0: virDomainGetState is the method state,
        # libvirt-override.c 2705-2739, generator.py 1140-1142, an answer of
        # None raised as libvirtError, generator.py 1659-1664.
        try:
            return self.kStateWords.get(self.connection.lookupByName(name).state(0)[0], self.kNoStateWord)
        except libvirt.libvirtError as error:
            self.log.note(f"{name}: no VM in libvirt's store ({error})")
            return self.kNoVm

    def press_key(self, name, code):
        # libvirt's send-key, as virsh send-key sends it: the Linux code set,
        # no hold time (tools/virsh-domain.c 9069-9079, 9112).
        with self._calls():
            self.connection.lookupByName(name).sendKey(libvirt.VIR_KEYCODE_SET_LINUX, 0, [code], 1, 0)

    def resize_disk(self, name, target, size):
        with self._calls():
            self.connection.lookupByName(name).blockResize(target, size, libvirt.VIR_DOMAIN_BLOCK_RESIZE_BYTES)

    def host_memory(self):
        with self._calls():
            return self.connection.getInfo()[1]

    def host_cpu_count(self):
        with self._calls():
            return self.connection.getInfo()[2]

    def capabilities(self):
        with self._calls():
            return ET.fromstring(self.connection.getCapabilities())

    def pci_devices(self):
        with self._calls():
            listed = self.connection.listAllDevices(libvirt.VIR_CONNECT_LIST_NODE_DEVICES_CAP_PCI_DEV)
            return [ET.fromstring(device.XMLDesc(0)) for device in listed]

    @contextlib.contextmanager
    def _calls(self):
        try:
            yield
        except libvirt.libvirtError as error:
            self.log.note(f"libvirt at {self.uri} refused a call: {error}")
            raise LibvirtCallFailed(str(error)) from error

    uri = ""
    log = None
    connection = None
    # The words virsh prints for a VM's state (virsh domstate), by libvirt's
    # state: libvirt v12.2.0 tools/virsh-domain-monitor.c 130-147 and 1323-1328,
    # the states include/libvirt/libvirt-domain.h 58-66.
    kStateWords = {
        libvirt.VIR_DOMAIN_NOSTATE: "no state", libvirt.VIR_DOMAIN_RUNNING: "running",
        libvirt.VIR_DOMAIN_BLOCKED: "idle", libvirt.VIR_DOMAIN_PAUSED: "paused",
        libvirt.VIR_DOMAIN_SHUTDOWN: "in shutdown", libvirt.VIR_DOMAIN_SHUTOFF: "shut off",
        libvirt.VIR_DOMAIN_CRASHED: "crashed", libvirt.VIR_DOMAIN_PMSUSPENDED: "pmsuspended",
    }
    kNoStateWord = kStateWords[libvirt.VIR_DOMAIN_NOSTATE]
    kRunningWord = kStateWords[libvirt.VIR_DOMAIN_RUNNING]
    kShutOffWord = kStateWords[libvirt.VIR_DOMAIN_SHUTOFF]
    kNoVm = ""
