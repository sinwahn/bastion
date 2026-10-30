from model.IpRange import IpRange
from model.NetworkIps import NetworkIps
from model.Refusals import Refusals
from user.NewNetwork import NewNetwork
from user.PicksScreen import PicksScreen
from user.Question import Choice, Question
from user.TextScreen import TextScreen
from user.TypedAnswerScreen import TypedAnswerScreen


class NewNetworkQuestions:
    """The questions of a new network, one screen each, then its summary; any question left ends them."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def ask(self):
        self.answers = NewNetwork()
        name = await self._ask_name()
        if not name:
            return
        vms = [vm for vm in self.state.vms if vm.has_station and not vm.nix]
        picked = await self._wait(PicksScreen(Question(title="2. VMs", choices=[
            Choice(vm.name, f"{vm.name}, on {vm.station.network}" + (", running: moves at its next start" if vm.active else ""))
            for vm in vms],
            meaning=f"the picked VMs move onto {name}; with none picked the network is made with no VM on it; "
                    "space or Enter picks and unpicks, ctrl+s goes on"), ()))
        if picked is PicksScreen.kBack:
            return
        moving = [vm for vm in vms if vm.name in picked]
        ip_range = NetworkIps(self.access.configuration).next_range(self.state.content)
        if await self._wait(TextScreen(self._summary(name, ip_range, moving))):
            self.answers.name = name
            self.answers.ip_range = ip_range
            self.answers.moving = moving

    def answered(self):
        """The answers; their name empty when a question is left."""
        return self.answers

    async def _ask_name(self):
        configuration = self.access.configuration
        firewall = configuration.firewall_vm
        refusals = Refusals(configuration)
        networks = self.state.content.networks
        return await self._wait(TypedAnswerScreen(Question(
            title="1. Name",
            meaning=f"letters, digits and dashes, at most {configuration.name_maximum} characters; "
                    f"the name is also {firewall}'s leg on this network"),
            lambda name: refusals.of_network_name(name, networks)))

    def _summary(self, name, ip_range, moving):
        firewall = self.access.configuration.firewall_vm
        now = ", ".join(vm.name for vm in moving if not vm.active)
        later = ", ".join(vm.name for vm in moving if vm.active)
        return (f"3. The network {name}:\n"
                f"range {ip_range}, {firewall}'s address on it {IpRange(ip_range).first()}\n"
                + (f"moving onto it now: {now}\n" if now else "")
                + (f"moving onto it at their next start: {later}\n" if later else "")
                + "\nEnter: make it.")

    async def _wait(self, screen):
        return await self.screen.app.push_screen_wait(screen)

    screen = None
    access = None
    state = None
    answers = NewNetwork()
