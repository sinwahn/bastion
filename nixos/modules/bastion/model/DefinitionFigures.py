from model.CpuSet import CpuSet
from model.Gigabytes import Gigabytes


class DefinitionFigures:
    """Figures read from a domain's definition: its RAM and the threads its vcpus are pinned to."""

    def memory_mib(self, element):
        return int(element.text) * Gigabytes.kUnitBytes.get(element.get("unit", "KiB"), 1024) // Gigabytes.kUnitBytes["MiB"]

    def first_pins(self, root):
        """Each vcpu's first pinned thread, in vcpu order."""
        pins = {}
        for pin in root.findall("./cputune/vcpupin"):
            pins[int(pin.get("vcpu"))] = CpuSet.parse(pin.get("cpuset"))
        return [pins[vcpu][0] for vcpu in sorted(pins) if pins[vcpu]]

    def all_pins(self, root):
        threads = []
        for pin in root.findall("./cputune/vcpupin"):
            threads.extend(CpuSet.parse(pin.get("cpuset")))
        return threads
