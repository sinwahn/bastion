from model.DefinitionEdit import DefinitionEdit
from model.DefinitionFigures import DefinitionFigures
from model.Gigabytes import Gigabytes
from model.HostThreads import HostThreads
from model.Offers import Offers
from model.Redefinition import Redefinition
from user.FastFirstAnswers import FastFirstAnswers
from user.GraphicsChoices import GraphicsChoices
from user.HostLines import HostLines
from user.Question import Choice, Question
from user.QuestionScreen import QuestionScreen
from user.VmLines import VmLines
from user.errors import NotSaved


class VmSettingChanges:
    """A VM's cores, fast cores first, RAM and graphics, each asked on its own screen and saved into its definition."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def change_cores(self, vm):
        threads = HostThreads(self.state.host)
        counts = Offers(self.access.configuration).thread_counts(self.state.host)
        picked = await self._ask(Question(title="Cores", choices=[
            Choice(str(count), f"{count} threads" + (" (now)" if count == vm.vcpus else "")) for count in counts],
            above=HostLines(self.state, self.access.configuration).holding(), meaning="takes effect at the VM's next start"))
        if not picked:
            return
        count = int(picked)
        pins = threads.pins(count, threads.preference_of(vm.pins), {}).threads
        edit = DefinitionEdit(threads)
        self._redefinition().apply(vm.name, lambda root: edit.set_cpu(root, count, pins))
        self._say_saved(vm, f"{self._redefinition().saved_definition(vm.name).findtext('vcpu')} threads")

    async def change_fast(self, vm):
        threads = HostThreads(self.state.host)
        answers = FastFirstAnswers()
        now = answers.answer(threads.preference_of(vm.pins))
        picked = await self._ask(Question(title="Fast cores first?", choices=[
            Choice("yes", "fast cores first: for VMs that need speed, such as games" + (" (now)" if now == "yes" else "")),
            Choice("no", "dense cores first, then fast ones" + (" (now)" if now == "no" else ""))],
            meaning="at each start the VM is pinned to free cores of its kind first"))
        if not picked:
            return
        pins = threads.pins(vm.vcpus, answers.preference(picked), {}).threads
        edit = DefinitionEdit(threads)
        self._redefinition().apply(vm.name, lambda root: edit.set_pins(root, pins))
        saved = self._redefinition().saved_definition(vm.name)
        self._say_saved(vm, f"{threads.preference_of(DefinitionFigures().first_pins(saved)).word()} cores first")

    async def change_ram(self, vm):
        sizes = Offers(self.access.configuration).ram_sizes(self.state.host)
        picked = await self._ask(Question(title="RAM", choices=[
            Choice(str(size), f"{size} GB" + (" (now)" if size * Gigabytes.kMibPerGib == vm.memory else "")) for size in sizes],
            above=HostLines(self.state, self.access.configuration).holding(), meaning="takes effect at the VM's next start"))
        if not picked:
            return
        edit = DefinitionEdit(HostThreads(self.state.host))
        self._redefinition().apply(vm.name, lambda root: edit.set_memory(root, int(picked) * Gigabytes.kMibPerGib))
        memory = DefinitionFigures().memory_mib(self._redefinition().saved_definition(vm.name).find("memory"))
        self._say_saved(vm, f"{Gigabytes.of_mebibytes(memory)} GB of RAM")

    async def change_graphics(self, vm):
        """The card given or taken; NotSaved when a card is picked and the host has no shared memory for looking-glass."""
        choices = GraphicsChoices(self.state, self.access.configuration)
        picked = await self._ask(Question(title="Graphics", choices=choices.choices(choices.now(vm)),
                                          meaning="takes effect at the VM's next start"))
        if not picked:
            return
        functions = choices.functions(picked)
        edit = DefinitionEdit(HostThreads(self.state.host))
        if functions:
            memory = self.access.shared_memory.read()
            if not memory.path:
                raise NotSaved("not saved: looking-glass's shared memory is not on the host.")
            self._redefinition().apply(vm.name, lambda root: edit.set_card(root, functions, memory))
        else:
            self._redefinition().apply(vm.name, edit.drop_card)
        self._say_saved(vm, choices.text(picked))

    def _redefinition(self):
        return Redefinition(self.state.libvirt, self.access.changes)

    def _say_saved(self, vm, what):
        self.screen.say(VmLines(self.state).saved(vm, what))

    async def _ask(self, question):
        return await self.screen.app.push_screen_wait(QuestionScreen(question))

    screen = None
    access = None
    state = None
