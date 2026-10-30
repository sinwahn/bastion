from model.GraphicsDevicesReading import GraphicsDevicesReading
from model.HostReading import HostReading
from model.State import State
from model.SystemFailures import SystemFailures
from model.VmReading import VmReading
from model.errors import FileNotDone, Refused


class StateReading:
    """The state the screens show, read fresh."""

    def __init__(self, access):
        self.access = access

    def read(self):
        with self.kFailures.raised_as_model():
            return self._read()

    def _read(self):
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
        except Refused as refusal:
            self.access.log.note(f"the live data file holds a refused value: {refusal}; the screens show it empty")
            state.content = live_data_file.empty()
            state.failure = live_data_file.refused_failure(refusal)
        except FileNotDone as error:
            self.access.log.note(f"the live data file cannot be read: {error}; the screens show it empty")
            state.content = live_data_file.empty()
            state.failure = live_data_file.unreadable_failure(error)

    access = None
    kFailures = SystemFailures()
