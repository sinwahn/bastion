from model.GraphicsDevicesReading import GraphicsDevicesReading
from model.HostReading import HostReading
from model.State import State
from model.VmReading import VmReading
from model.errors import Refused
from system.errors import FileFailed


class StateReading:
    """The state the screens show, read fresh."""

    def __init__(self, access):
        self.access = access

    def read(self):
        state = State()
        state.libvirt = self.access.libvirt.open()
        state.host = HostReading(state.libvirt, self.access.files, self.access.configuration.images_folder).read()
        self._read_live_data(state)
        nix_names = self.access.nix_domains.names()
        reading = VmReading(state.libvirt, self.access.configuration)
        vms = [reading.read(name, state.content, nix_names) for name in state.libvirt.domain_names()]
        state.vms = sorted(vms, key=lambda vm: vm.name)
        state.devices = GraphicsDevicesReading(state.libvirt).read(state.vms)
        return state

    def _read_live_data(self, state):
        live_data_file = self.access.live_data_file
        try:
            state.content = live_data_file.read_checked()
        except (FileFailed, Refused) as error:
            self.access.log.note(f"the live data file cannot be read: {error}; the screens show it empty")
            state.content = live_data_file.empty()
            state.failure = live_data_file.failure_of(error)

    access = None
