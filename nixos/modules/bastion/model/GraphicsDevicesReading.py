from model.GraphicsDevice import GraphicsDevice
from model.PciFunctions import PciFunctions


class GraphicsDevicesReading:
    """Every graphics device of the host, from libvirt's node devices."""

    # A device that is a hostdev in some VM's definition is held by one VM at
    # a time, with the functions of its IOMMU group that definitions list;
    # any other device is the host's.

    def __init__(self, libvirt):
        self.libvirt = libvirt

    def read(self, vms):
        listed = {function for vm in vms for function in vm.hostdevs}
        devices = {}
        for element in self.libvirt.pci_devices():
            capability = element.find("./capability[@type='pci']")
            if capability is not None:
                device = self._device(element, capability)
                devices[device.function] = device
        found = [device for _, device in sorted(devices.items()) if self._is_display(device)]
        for device in found:
            self._read_use(device, listed, vms)
        return found

    def _device(self, element, capability):
        device = GraphicsDevice()
        device.function = self.kFunctions.from_capability(capability)
        device.device_class = capability.findtext("class")
        device.driver = element.findtext("./driver/name") or ""
        device.name = self._name(capability)
        device.group = [self.kFunctions.from_element(member) for member in capability.findall("./iommuGroup/address")]
        return device

    def _name(self, capability):
        product = capability.find("product")
        vendor = capability.find("vendor")
        return (product.text if product is not None and product.text else "") or \
            f"{vendor.get('id') if vendor is not None else ''}:{product.get('id') if product is not None else ''}"

    def _is_display(self, device):
        return bool(device.device_class) and int(device.device_class, 16) >> 16 == self.kDisplayClass

    def _read_use(self, device, listed, vms):
        device.passthrough = device.function in listed
        if device.passthrough:
            device.functions = [member for member in device.group if member in listed] or [device.function]
        device.holders = [vm.name for vm in vms if vm.active and set(vm.live_hostdevs) & set(device.functions)]

    libvirt = None
    kFunctions = PciFunctions()
    # A display device: the PCI base class of the kernel's header
    # include/linux/pci_ids.h (PCI_BASE_CLASS_DISPLAY), the class's top byte.
    kDisplayClass = 0x03
