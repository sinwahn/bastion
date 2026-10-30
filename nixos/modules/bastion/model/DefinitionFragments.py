import xml.etree.ElementTree as ET


class DefinitionFragments:
    """The parts of a domain's definition the tool writes, and a definition's text."""

    def cputune(self, pins, threads):
        lines = [f"<vcpupin vcpu='{index}' cpuset='{thread}'/>" for index, thread in enumerate(pins)]
        emulator = threads.emulator_threads()
        if emulator:
            lines.append(f"<emulatorpin cpuset='{emulator}'/>")
        return "<cputune>" + "".join(lines) + "</cputune>"

    def hostdev(self, function):
        return ("<hostdev mode='subsystem' type='pci' managed='no'><source>"
                f"<address domain='0x{function.domain:04x}' bus='0x{function.bus:02x}' slot='0x{function.slot:02x}' function='0x{function.function:x}'/>"
                "</source></hostdev>")

    def commandline(self, memory):
        return (f"<qemu:commandline xmlns:qemu='{self.kQemuNamespace}'>"
                "<qemu:arg value='-device'/>"
                "<qemu:arg value=\"{'driver':'ivshmem-plain','id':'shmem0','memdev':'looking-glass'}\"/>"
                "<qemu:arg value='-object'/>"
                f"<qemu:arg value=\"{{'qom-type':'memory-backend-file','id':'looking-glass','mem-path':'{memory.path}','size':{memory.size},'share':true}}\"/>"
                "</qemu:commandline>")

    def vsock(self, number):
        return f"<vsock model='virtio'><cid auto='no' address='{number}'/></vsock>"

    def text(self, root):
        ET.register_namespace("qemu", self.kQemuNamespace)
        return ET.tostring(root, encoding="unicode")

    kQemuNamespace = "http://libvirt.org/schemas/domain/qemu/1.0"
