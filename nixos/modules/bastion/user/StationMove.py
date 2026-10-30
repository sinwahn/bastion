from model.CableEdit import CableEdit
from model.LiveDataWriting import LiveDataWriting
from model.NetworkIps import NetworkIps
from model.Redefinition import Redefinition
from model.StationEdit import StationEdit
from user.AppliedLine import AppliedLine
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.ScreenSteps import ScreenSteps


class StationMove:
    """A VM moved to a network: an off VM at once, its definition and its station with an IP of the new network; a running VM's definition alone, its station following at its next start."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def move(self, vm):
        content = self.state.content
        station = content.stations[vm.name]
        edit = CableEdit(self.access.configuration.switch)
        there = edit.network_of(vm.root, content)
        target = await self.screen.app.push_screen_wait(QuestionScreen(Question(
            title=f"Move {vm.name} to a network",
            choices=[Choice(name, f"{name}: {entry.ip_range}" + (" (now)" if name == station.network else ""),
                            name == station.network and name == there)
                     for name, entry in content.networks.items()],
            meaning="an off VM moves at once and gets an address of that network; "
                    "a running VM moves at its next start")))
        if not target:
            return
        Redefinition(self.state.libvirt, self.access.changes).apply(vm.name, lambda root: edit.set_lane(root, content, target))
        if vm.active:
            self.screen.say("saved: takes effect at its next start")
            return
        self._move_station(vm.name, target)

    def _move_station(self, name, target):
        content = self.access.live_data_file.read()
        station = content.stations[name]
        if station.network == target:
            self.screen.say(f"saved: {name} is on {target}")
            return
        stations = StationEdit(self.access.configuration.exchange.sends_to)
        stations.set_network(station, target)
        stations.set_ip(station, NetworkIps(self.access.configuration).free_ip(content, target))
        applied = AppliedLine(LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access))
        applied.write(content)
        self.screen.say(applied.line())

    screen = None
    access = None
    state = None
