import xml.etree.ElementTree as ET

from model.DefinitionFragments import DefinitionFragments


class WindowsDefinition:
    """A Windows VM's definition; its cable's network part (vlan and port) is set_lane's."""

    def __init__(self, configuration, threads):
        self.configuration = configuration
        self.threads = threads

    def root(self, request):
        return ET.fromstring(self._text(request))

    def _text(self, request):
        return (self._opening(request) + self.kFragments.cputune(request.pins, self.threads)
                + self._firmware(request) + self._devices(request) + self._closing(request))

    def _opening(self, request):
        name, uuid, memory, vcpus = request.name, request.uuid, request.memory, request.vcpus
        return (
            f"<domain type='kvm' xmlns:qemu='{DefinitionFragments.kQemuNamespace}'>"
            f"<name>{name}</name>"
            + (f"<uuid>{uuid}</uuid>" if uuid else "")
            + f"<memory unit='MiB'>{memory}</memory><currentMemory unit='MiB'>{memory}</currentMemory>"
            f"<vcpu placement='static'>{vcpus}</vcpu>")

    def _firmware(self, request):
        win11 = request.win11
        secure_boot = "yes" if win11 else "no"
        per_core = self.threads.host.threads_per_core
        return (
            "<os firmware='efi'><type arch='x86_64' machine='q35'>hvm</type><firmware>"
            f"<feature enabled='{secure_boot}' name='secure-boot'/>"
            + ("<feature enabled='no' name='enrolled-keys'/>" if win11 else "")
            + "</firmware></os>"
            "<features><acpi/><apic/><hyperv mode='custom'><relaxed state='on'/><vapic state='on'/>"
            "<spinlocks state='on' retries='8191'/><vpindex state='on'/><synic state='on'/>"
            "<stimer state='on'/><frequencies state='on'/></hyperv>"
            + ("<smm state='on'/>" if win11 else "")
            + "</features>"
            "<cpu mode='host-passthrough' check='none' migratable='off'>"
            f"<topology sockets='1' dies='1' clusters='1' cores='{max(request.vcpus // per_core, 1)}' threads='{per_core}'/>"
            + ("<cache mode='passthrough'/>" if request.functions else ""))

    def _devices(self, request):
        disk, mac, name = request.disk, request.mac, request.name
        return (
            "</cpu>"
            "<clock offset='localtime'><timer name='rtc' tickpolicy='catchup'/><timer name='pit' tickpolicy='delay'/>"
            "<timer name='hpet' present='no'/><timer name='hypervclock' present='yes'/></clock>"
            "<on_poweroff>destroy</on_poweroff><on_reboot>restart</on_reboot><on_crash>destroy</on_crash>"
            "<pm><suspend-to-mem enabled='no'/><suspend-to-disk enabled='no'/></pm>"
            "<devices>"
            f"<disk type='file' device='disk'><driver name='qemu' type='qcow2' discard='unmap'/>"
            f"<source file='{disk}'/><target dev='vda' bus='virtio'/><boot order='1'/></disk>"
            + self._cdroms(request)
            + "<controller type='usb' model='qemu-xhci'/>"
            "<interface type='bridge'>"
            + (f"<mac address='{mac}'/>" if mac else "")
            + f"<source bridge='{self.configuration.switch}'/><target dev='{name}'/><model type='virtio'/>"
            "</interface>"
            "<input type='tablet' bus='usb'/>"
            "<graphics type='spice' autoport='yes'><listen type='address' address='127.0.0.1'/>"
            "<clipboard copypaste='no'/><filetransfer enable='no'/></graphics>"
            "<video><model type='qxl'/></video><sound model='ich9'/><audio id='1' type='spice'/>"
            + ("<tpm model='tpm-crb'><backend type='emulator' version='2.0'/></tpm>" if request.win11 else "")
            + "<memballoon model='none'/>"
            + "".join(self.kFragments.hostdev(function) for function in request.functions)
            + "</devices>")

    def _cdroms(self, request):
        iso = request.iso
        if not iso:
            return ""
        return (f"<disk type='file' device='cdrom'><driver name='qemu' type='raw'/><source file='{iso}'/>"
                "<target dev='sda' bus='sata'/><readonly/><boot order='2'/></disk>"
                f"<disk type='file' device='cdrom'><driver name='qemu' type='raw'/><source file='{self.configuration.virtio_iso}'/>"
                "<target dev='sdb' bus='sata'/><readonly/></disk>")

    def _closing(self, request):
        return (self.kFragments.commandline(request.shared_memory) if request.functions else "") + "</domain>"

    configuration = None
    threads = None
    kFragments = DefinitionFragments()
