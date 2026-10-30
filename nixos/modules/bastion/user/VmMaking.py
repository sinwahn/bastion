import os
import xml.etree.ElementTree as ET

from model.CableEdit import CableEdit
from model.DefinitionFragments import DefinitionFragments
from model.DefinitionRequest import DefinitionRequest
from model.Gigabytes import Gigabytes
from model.HostThreads import HostThreads
from model.LiveDataWriting import LiveDataWriting
from model.NetworkIps import NetworkIps
from model.StationEdit import StationEdit
from model.WindowsDefinition import WindowsDefinition
from model.preferences.DenseFirst import DenseFirst
from model.preferences.FastFirst import FastFirst
from system.PrivilegedSteps import StepCall
from system.errors import LibvirtCallFailed, StepFailed
from user.GraphicsChoices import GraphicsChoices
from user.ScreenSteps import ScreenSteps
from user.TextScreen import TextScreen


class VmMaking:
    """A new VM made from the answers: its disk by make-disk, its definition, and its station by networks-write."""

    def __init__(self, screen, access, state):
        self.screen = screen
        self.access = access
        self.state = state

    async def make(self, new_vm):
        name = new_vm.name
        steps = ScreenSteps(self.screen.app, self.access.privileged_steps)
        call = StepCall(step="make-disk", arguments=[new_vm.template.word, name, str(new_vm.disk)],
                        note=f"make-disk copies {new_vm.template.word} into {name}'s disk (a few minutes; sudo may ask your password) ...")
        try:
            steps.run(call)
        except StepFailed as failure:
            self.screen.say(f"{name} is not made: make-disk failed: {failure.answer.output}")
            return
        request = self._request(new_vm)
        if request.functions and not request.shared_memory.path:
            self.screen.say(f"{name}'s disk is made, the VM is not: looking-glass's shared memory is not on the host.")
            return
        content = self.access.live_data_file.read()
        try:
            mac = self._define(request, content, new_vm.network)
        except LibvirtCallFailed as error:
            self.screen.say(f"{name}'s disk is made, the VM is not defined: {error}")
            return
        await self._write_station(new_vm, content, mac)

    def _request(self, new_vm):
        threads = HostThreads(self.state.host)
        request = DefinitionRequest(name=new_vm.name, memory=new_vm.ram * Gigabytes.kMibPerGib, vcpus=new_vm.cores,
                                    disk=os.path.join(self.access.configuration.images_folder, new_vm.name + ".qcow2"),
                                    win11=new_vm.template.win11)
        request.pins = threads.pins(new_vm.cores, self.kPreferences[new_vm.fast_first], {}).threads
        request.functions = GraphicsChoices(self.state, self.access.configuration).functions(new_vm.card)
        if request.functions:
            request.shared_memory = self.access.shared_memory.read()
        return request

    def _define(self, request, content, network):
        """The VM defined on network; its MAC, which libvirt gives it."""
        threads = HostThreads(self.state.host)
        root = ET.fromstring(WindowsDefinition(self.access.configuration, threads).text(request))
        CableEdit(self.access.configuration.switch).set_lane(root, content, network)
        libvirt = self.state.libvirt
        libvirt.define(DefinitionFragments().text(root))
        self.access.changes.add(request.name)
        return libvirt.definition(request.name).find("./devices/interface/mac").get("address")

    async def _write_station(self, new_vm, content, mac):
        # A name's entry taken over keeps every key it has, its mac the new
        # VM's; any other name gets an entry with the network's next free IP.
        name = new_vm.name
        edit = StationEdit(self.access.configuration.exchange.sends_to)
        if name in content.stations:
            entry = content.stations[name]
            edit.set_mac(entry, mac)
        else:
            entry = edit.made(new_vm.network, NetworkIps(self.access.configuration).free_ip(content, new_vm.network), mac)
            edit.set_rule(entry, new_vm.rule, new_vm.names)
            content.stations[name] = entry
        writing = LiveDataWriting(ScreenSteps(self.screen.app, self.access.privileged_steps), self.access)
        try:
            output = writing.write(content)
        except StepFailed as failure:
            self.screen.action_read()
            self.screen.say(f"{name} is defined; its address and rule were not applied: {failure.answer.output}")
            return
        self.screen.action_read()
        await self.screen.app.push_screen_wait(TextScreen(
            f"{name} is made: address {entry.ip}, internet {new_vm.rule}.\n{output}\n\n"
            f"Its first start: open it and pick 'first start'; that start runs without network."))

    screen = None
    access = None
    state = None
    kPreferences = {"yes": FastFirst(), "no": DenseFirst()}
