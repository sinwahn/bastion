import xml.etree.ElementTree as ET

from model.DefinitionFragments import DefinitionFragments


class DefinitionEdit:
    """Changes to a domain's definition: its pins, vcpus, RAM, vsock device, card and looking-glass block."""

    def __init__(self, threads):
        self.threads = threads

    def set_pins(self, root, pins):
        for cputune in root.findall("cputune"):
            root.remove(cputune)
        vcpu = root.find("vcpu")
        root.insert(list(root).index(vcpu) + 1, ET.fromstring(self.kFragments.cputune(pins, self.threads)))

    def set_cpu(self, root, vcpus, pins):
        root.find("vcpu").text = str(vcpus)
        self.set_pins(root, pins)
        topology = root.find("./cpu/topology")
        if topology is not None:
            per_core = self.threads.host.threads_per_core
            topology.set("cores", str(max(vcpus // per_core, 1)))
            topology.set("threads", str(per_core))

    def set_memory(self, root, mib):
        for tag in ("memory", "currentMemory"):
            element = root.find(tag)
            element.text = str(mib)
            element.set("unit", "MiB")

    def set_vsock(self, root, number):
        """The vsock device with number in place of any the definition holds, since libvirt takes one only."""
        # libvirt v12.2.0 docs/formatdomain.rst 9425-9445, src/conf/domain_conf.c
        # 20583-20588; a start sets it for that start alone.
        devices = root.find("devices")
        for old in devices.findall("vsock"):
            devices.remove(old)
        devices.append(ET.fromstring(self.kFragments.vsock(number)))

    def set_glass(self, root, memory):
        """Glass on: the looking-glass block added again, in place of every qemu:commandline element."""
        self.drop_glass(root)
        root.append(ET.fromstring(self.kFragments.commandline(memory)))

    def drop_glass(self, root):
        """Glass off: every qemu:commandline element of the definition removed."""
        for commandline in root.findall(f"{{{DefinitionFragments.kQemuNamespace}}}commandline"):
            root.remove(commandline)

    def set_card(self, root, functions, memory):
        """The card given, with the looking-glass block, so glass is on until it is turned off."""
        self.drop_card(root)
        self.set_glass(root, memory)
        devices = root.find("devices")
        for function in functions:
            devices.append(ET.fromstring(self.kFragments.hostdev(function)))
        root.find("cpu").append(ET.fromstring("<cache mode='passthrough'/>"))

    def drop_card(self, root):
        devices = root.find("devices")
        for hostdev in devices.findall("hostdev"):
            if hostdev.get("type") == "pci":
                devices.remove(hostdev)
        cpu = root.find("cpu")
        for cache in cpu.findall("cache"):
            cpu.remove(cache)
        self.drop_glass(root)

    threads = None
    kFragments = DefinitionFragments()
