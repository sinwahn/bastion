from model.Gigabytes import Gigabytes
from model.HostThreads import HostThreads
from model.Offers import Offers
from model.Refusals import Refusals
from model.enums import InternetRule, ThreadKind
from user.GraphicsChoices import GraphicsChoices
from user.HostLines import HostLines
from user.NewVm import NewVm
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.RuleChange import RuleChange
from user.TextScreen import TextScreen
from user.TypedAnswerScreen import TypedAnswerScreen


class NewVmQuestions:
    """The questions of a new VM, one screen each, then its summary; any question left ends them."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def ask(self):
        """The answers; an empty name when a question is left or the disk has no room."""
        new_vm = NewVm()
        for step in (self._ask_name, self._ask_template, self._ask_cores, self._ask_fast, self._ask_ram,
                     self._ask_disk, self._ask_graphics, self._ask_network, self._confirm):
            if not await step(new_vm):
                return NewVm()
        return new_vm

    async def _ask_name(self, new_vm):
        configuration = self.access.configuration
        used = {vm.name for vm in self.state.vms} | set(configuration.names_in_use)
        retired = set(self.access.files.list_folder(configuration.retired_folder)) if self.access.files.is_folder(configuration.retired_folder) else set()
        refusals = Refusals(configuration)
        question = Question(title="1. Name", meaning=f"letters, digits and dashes, at most {configuration.name_maximum} characters; the name is also the VM's cable")
        new_vm.name = await self._wait(TypedAnswerScreen(question, lambda name: refusals.of_vm_name(name, used, retired)))
        # The name's entry in the live data file, which no VM stands behind:
        # the new VM takes it over, its network, IP and internet rule kept.
        new_vm.has_station = new_vm.name in self.state.content.stations
        if new_vm.has_station:
            new_vm.station = self.state.content.stations[new_vm.name]
        return bool(new_vm.name)

    async def _ask_template(self, new_vm):
        choices = []
        for template in self.access.configuration.templates:
            ready = self.access.templates.is_sealed(template)
            choices.append(Choice(template.word, template.word if ready else f"{template.word}: not ready: install Windows in it first", not ready))
        word = await self._ask(Question(title="2. Windows", choices=choices, meaning="the VM is an independent copy of the sealed template"))
        if word:
            new_vm.template = self.access.templates.template(word)
        return bool(word)

    async def _ask_cores(self, new_vm):
        counts = Offers(self.access.configuration).thread_counts(self.state.host)
        cores = await self._ask(Question(title="3. Cores", choices=[Choice(str(count), f"{count} threads") for count in counts],
                                         above=HostLines(self.state, self.access.configuration).holding(),
                                         meaning="only counts that fit are offered; a start is refused while the running VMs together would pass the host"))
        new_vm.cores = int(cores or 0)
        return bool(cores)

    async def _ask_fast(self, new_vm):
        threads = HostThreads(self.state.host)
        new_vm.fast_first = await self._ask(Question(title="3b. Fast cores first?", choices=[
            Choice("yes", f"fast cores first ({threads.count(ThreadKind.kFast)} fast threads on this host): for VMs that need speed, such as games"),
            Choice("no", f"dense cores first ({threads.count(ThreadKind.kDense)} dense threads), then fast ones")],
            meaning="at each start the VM is pinned to free cores of its kind first; the start screen says when it shares"))
        return bool(new_vm.fast_first)

    async def _ask_ram(self, new_vm):
        sizes = Offers(self.access.configuration).ram_sizes(self.state.host)
        ram = await self._ask(Question(title="4. RAM", choices=[Choice(str(size), f"{size} GB") for size in sizes],
                                       above=HostLines(self.state, self.access.configuration).holding(), meaning="RAM the VM gets while it runs"))
        new_vm.ram = int(ram or 0)
        return bool(ram)

    async def _ask_disk(self, new_vm):
        offers = Offers(self.access.configuration)
        room = offers.disk_room(self.state.host, self.state.vms)
        sizes = offers.new_disk_sizes(new_vm.template.disk, room)
        if not sizes:
            await self._wait(TextScreen(f"The disk has room for no new VM: {max(room, 0) // Gigabytes.kGib} GB are free for VM disks, "
                                        f"the template needs {new_vm.template.disk} GB."))
            return False
        disk = await self._ask(Question(title="5. Disk", choices=[Choice(str(size), f"{size} GB") for size in sizes],
                                        above=HostLines(self.state, self.access.configuration).disk(),
                                        meaning="a disk can be made bigger later, never smaller"))
        new_vm.disk = int(disk or 0)
        return bool(disk)

    async def _ask_graphics(self, new_vm):
        new_vm.card = await self._ask(Question(title="6. Graphics", choices=GraphicsChoices(self.state, self.access.configuration).choices(""),
                                               meaning="a VM with a card shows its screen through looking-glass"))
        return bool(new_vm.card)

    async def _ask_network(self, new_vm):
        if new_vm.has_station:
            new_vm.network, new_vm.rule, new_vm.names = new_vm.station.network, new_vm.station.rule, new_vm.station.names
            return True
        new_vm.network = await self._ask(Question(title="7. Network", choices=[Choice(name, name) for name in self.state.content.networks],
                                                  meaning="the network the VM's cable is on"))
        if not new_vm.network:
            return False
        answer = await RuleChange(self.screen, self.access).ask("", [])
        new_vm.rule, new_vm.names = answer.rule, answer.names
        return bool(new_vm.rule)

    async def _confirm(self, new_vm):
        name, rule, names = new_vm.name, new_vm.rule, new_vm.names
        graphics = GraphicsChoices(self.state, self.access.configuration).text(new_vm.card)
        summary = (f"8. The VM {name}:\n"
                   f"  Windows: {new_vm.template.word}\n  cores: {new_vm.cores} threads, {'fast' if new_vm.fast_first == 'yes' else 'dense'} cores first\n"
                   f"  RAM: {new_vm.ram} GB\n  disk: {new_vm.disk} GB\n  graphics: {graphics}\n"
                   f"  network: {new_vm.network}\n  internet: {rule}" + (f" ({', '.join(names)})" if rule == InternetRule.kListed.value else "")
                   + (f"\n  network and internet rule: from {name}'s existing entry in networks.json" if new_vm.has_station else "")
                   + "\n\nEnter: make it.")
        return await self._wait(TextScreen(summary))

    async def _ask(self, question):
        return await self._wait(QuestionScreen(question))

    async def _wait(self, screen):
        return await self.screen.app.push_screen_wait(screen)

    screen = None
    access = None
    state = None
