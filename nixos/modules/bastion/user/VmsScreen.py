from textual import work
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import DataTable, Footer, Header, OptionList, Static
from textual.widgets.option_list import Option

from model.StateReading import StateReading
from system.errors import LibvirtCallFailed
from user.CopyNotice import CopyNotice
from user.FirmwareCopy import FirmwareCopy
from user.NewVmQuestions import NewVmQuestions
from user.PlainText import PlainText
from user.Question import Choice
from user.VmLines import VmLines
from user.VmMaking import VmMaking
from user.VmScreen import VmScreen
from user.VmsRestore import VmsRestore


class VmsScreen(Screen):
    """The VMs section: the VMs, a new VM, and the two actions of the copy folder, "copy firmware and TPM" and "restore"."""
    BINDINGS = [Binding("n", "new", "new VM"), Binding("r", "read", "read again"),
                Binding("escape", "app.pop_screen", "back")]

    def __init__(self, access):
        super().__init__()
        self.access = access

    def compose(self):
        yield Header()
        yield DataTable(cursor_type="row", id="vms")
        yield OptionList(*[Option(PlainText.of(choice.words), id=choice.identifier) for choice in self.kActions], id="actions")
        yield Static(PlainText.of(""), markup=False, id="message")
        yield Footer()

    def on_option_list_option_selected(self, event):
        if event.option_list.id == "actions":
            {"copy": self.copy_state, "restore": self.restore}[event.option_id]()

    @work(exclusive=True)
    async def copy_state(self):
        FirmwareCopy(self, self.access).run()

    @work(exclusive=True)
    async def restore(self):
        await VmsRestore(self, self.access).run()

    def on_mount(self):
        self.sub_title = "VMs"

    def on_screen_resume(self):
        self.action_read()

    def say(self, body):
        self.query_one("#message", Static).update(PlainText.of(body))

    def action_read(self):
        table = self.query_one(DataTable)
        table.clear(columns=True)
        table.add_columns(*[PlainText.of(column) for column in ("name", "state", "cores", "RAM", "disk", "graphics",
                                                                "network", "internet rule")])
        try:
            state = StateReading(self.access).read()
        except LibvirtCallFailed as error:
            self.say(f"libvirt cannot be read: {error}")
            return
        lines = VmLines(state)
        for vm in state.vms:
            table.add_row(*[PlainText.of(cell) for cell in lines.row(vm)], key=vm.name)

    def on_data_table_row_selected(self, event):
        self.app.push_screen(VmScreen(self.access, event.row_key.value))

    def action_new(self):
        self.new_vm()

    @work(exclusive=True)
    async def new_vm(self):
        state = StateReading(self.access).read()
        new_vm = await NewVmQuestions(self, self.access, state).ask()
        if not new_vm.name:
            return
        await VmMaking(self, self.access, state).make(new_vm)
        CopyNotice(self.app, self.access).write()

    access = None
    kActions = [Choice("copy", "copy firmware and TPM"), Choice("restore", "restore")]
