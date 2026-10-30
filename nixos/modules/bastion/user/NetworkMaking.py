from model.CableEdit import CableEdit
from model.LiveDataWriting import LiveDataWriting
from model.NetworkIps import NetworkIps
from model.Redefinition import Redefinition
from model.StationEdit import StationEdit
from user.AppliedLine import AppliedLine
from user.ScreenSteps import ScreenSteps


class NetworkMaking:
    """The new network written into the live data file with the VMs moving onto it: each one's definition first, then the one networks-write."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    def make(self, answers):
        configuration = self.access.configuration
        content = self.access.live_data_file.read()
        ips = NetworkIps(configuration)
        content.networks[answers.name] = ips.made(content, answers.ip_range)
        edit = CableEdit(configuration.switch)
        redefinition = Redefinition(self.state.libvirt, self.access.changes)
        stations = StationEdit(configuration.exchange.sends_to)
        for vm in answers.moving:
            redefinition.apply(vm.name, lambda root: edit.set_lane(root, content, answers.name))
            if not vm.active:
                stations.set_network(content.stations[vm.name], answers.name)
                stations.set_ip(content.stations[vm.name], ips.free_ip(content, answers.name))
        applied = AppliedLine(LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access))
        applied.write(content)
        self.screen.say(applied.line())

    screen = None
    access = None
    state = None
