from model.LiveDataWriting import LiveDataWriting
from model.StateVms import StateVms
from model.StationEdit import StationEdit
from user.AppliedLine import AppliedLine
from user.BrokerLines import BrokerLines
from user.PicksScreen import PicksScreen
from user.Question import Choice, Question
from user.ScreenSteps import ScreenSteps


class DestinationsChange:
    """A VM's list of destinations: one pick of every other VM the tool owns, the host's station name, and each listed name with no VM defined now, marked, the listed ones picked."""

    # ctrl+s writes the picked names, in the pick's order, as its station's
    # list through networks-write, and an empty pick removes the key.

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def change(self, vm):
        configuration = self.access.configuration
        content = self.access.live_data_file.read()
        has_station = vm.name in content.stations
        now = content.stations[vm.name].destinations if has_station else []
        lines = BrokerLines(self.state, configuration)
        offered = self._offered(vm, now)
        picked = await self.screen.app.push_screen_wait(PicksScreen(Question(
            title=f"{vm.name}: {configuration.exchange.sends_to_label}",
            choices=[Choice(name, lines.name(name)) for name in offered],
            meaning="space or Enter picks and unpicks, ctrl+s saves"), now))
        if picked is PicksScreen.kBack:
            return
        if not has_station:
            self.screen.say(f"{vm.name} has no entry in networks.json.")
            return
        names = [name for name in offered if name in picked]
        stations = StationEdit(configuration.exchange.sends_to)
        if names:
            stations.set_destinations(content.stations[vm.name], names)
        else:
            stations.drop_destinations(content.stations[vm.name])
        applied = AppliedLine(LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access))
        applied.write(content)
        self.screen.say(applied.line())

    def _offered(self, vm, now):
        host = self.access.configuration.host_port
        vms = StateVms(self.state)
        owned = [other.name for other in BrokerLines(self.state, self.access.configuration).vms() if other.name != vm.name]
        return owned + [host] + [name for name in now if name != host and not vms.has(name)]

    screen = None
    access = None
    state = None
