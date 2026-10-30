from model.CableEdit import CableEdit
from model.FollowOutcome import FollowOutcome
from model.NetworkIps import NetworkIps
from model.StationEdit import StationEdit
from model.errors import LiveDataNotApplied


class StationFollow:
    """Before a start: when a VM's definition puts it on another network than its station's (a move saved while it ran), the station takes that network and its next free IP, in one networks-write."""

    def __init__(self, writing, access):
        self.writing = writing
        self.access = access

    def follow(self, vm):
        self.result = FollowOutcome()
        if not vm.has_station:
            return
        content = self.access.live_data_file.read()
        target = CableEdit(self.access.configuration.switch).network_of(vm.root, content)
        if vm.name not in content.stations or not target or content.stations[vm.name].network == target:
            return
        self._move(content, vm.name, target)
        self.result.moved = True
        try:
            self.writing.write(content)
        except LiveDataNotApplied as failure:
            self.result.output = str(failure)
            return
        self.result.output = self.writing.answer()
        self.result.applied = True

    def outcome(self):
        return self.result

    def _move(self, content, name, network):
        edit = StationEdit(self.access.configuration.exchange.sends_to)
        edit.set_network(content.stations[name], network)
        edit.set_ip(content.stations[name], NetworkIps(self.access.configuration).free_ip(content, network))

    writing = None
    access = None
    result = FollowOutcome()
