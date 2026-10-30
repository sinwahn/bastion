from model.PciFunction import PciFunction


class PciFunctions:
    """PCI functions read from libvirt's XML and written the way lspci writes them."""

    def from_element(self, element):
        numbers = [int(element.get(key), 16) for key in self.kParts]
        return self._function(numbers)

    def from_capability(self, capability):
        numbers = [int(capability.findtext(key)) for key in self.kParts]
        return self._function(numbers)

    def given(self, root):
        """The PCI functions a definition gives its VM."""
        return [self.from_element(element) for element in root.findall("./devices/hostdev[@type='pci']/source/address")]

    def text(self, function):
        return f"{function.domain:04x}:{function.bus:02x}:{function.slot:02x}.{function.function:x}"

    def _function(self, numbers):
        function = PciFunction()
        function.domain, function.bus, function.slot, function.function = numbers
        return function

    kParts = ("domain", "bus", "slot", "function")
