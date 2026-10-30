from model.DefinitionFigures import DefinitionFigures
from model.DefinitionFragments import DefinitionFragments
from model.PciFunctions import PciFunctions
from model.Vm import Vm


class VmReading:
    """A VM read from libvirt's store and the live data file."""

    def __init__(self, libvirt, configuration):
        self.libvirt = libvirt
        self.configuration = configuration

    def read(self, name, content, nix_names):
        vm = Vm()
        vm.name = name
        vm.root = self.libvirt.definition(name)
        vm.active = self.libvirt.is_active(name)
        vm.vcpus = int(vm.root.findtext("vcpu"))
        vm.memory = self.kFigures.memory_mib(vm.root.find("memory"))
        vm.glass = vm.root.find(f"{{{DefinitionFragments.kQemuNamespace}}}commandline") is not None
        vm.hostdevs = self.kFunctions.given(vm.root)
        vm.pins = self.kFigures.first_pins(vm.root)
        self._read_disk(vm)
        self._read_live(vm)
        vm.has_station = name in content.stations
        if vm.has_station:
            vm.station = content.stations[name]
        vm.template = any(template.name == name for template in self.configuration.templates)
        vm.nix = name in nix_names
        return vm

    def _read_disk(self, vm):
        disk = vm.root.find("./devices/disk[@device='disk']")
        if disk is None:
            return
        vm.disk_file = disk.find("source").get("file")
        vm.disk_target = disk.find("target").get("dev")
        if vm.disk_target:
            sizes = self.libvirt.disk_sizes(vm.name, vm.disk_target)
            vm.capacity = sizes.capacity
            vm.allocation = sizes.allocation

    def _read_live(self, vm):
        if not vm.active:
            vm.live_hostdevs = vm.hostdevs
            return
        live = self.libvirt.live_definition(vm.name)
        vm.live_hostdevs = self.kFunctions.given(live)
        vm.live_pins = self.kFigures.all_pins(live)
        vsock = live.find("./devices/vsock/cid")
        if vsock is not None:
            vm.live_vsock = int(vsock.get("address"))

    libvirt = None
    configuration = None
    kFigures = DefinitionFigures()
    kFunctions = PciFunctions()
