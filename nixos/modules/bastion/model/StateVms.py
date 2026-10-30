from model.errors import VmMissing


class StateVms:
    """The VMs of a state: by name, the running ones and the threads they hold."""

    def __init__(self, state):
        self.state = state

    def has(self, name):
        return any(vm.name == name for vm in self.state.vms)

    def vm(self, name):
        for vm in self.state.vms:
            if vm.name == name:
                return vm
        raise VmMissing(name)

    def running(self):
        return [vm for vm in self.state.vms if vm.active]

    def taken(self):
        """{thread: [running VMs pinned there]}."""
        return self.taken_without("")

    def taken_without(self, name):
        """{thread: [running VMs pinned there]}, the VM name left out."""
        taken = {}
        for vm in self.running():
            if vm.name != name:
                for thread in vm.live_pins:
                    taken.setdefault(thread, []).append(vm.name)
        return taken

    def given_card(self, vm):
        """The devices whose functions vm's definition gives it."""
        return [device for device in self.state.devices if set(vm.hostdevs) & set(device.functions)]

    state = None
