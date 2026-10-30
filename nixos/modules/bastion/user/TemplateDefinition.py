from model.CableEdit import CableEdit
from model.DefinitionFragments import DefinitionFragments
from model.DefinitionRequest import DefinitionRequest
from model.HostReading import HostReading
from model.HostThreads import HostThreads
from model.WindowsDefinition import WindowsDefinition
from model.preferences.DenseFirst import DenseFirst
from system.PrivilegedSteps import StepCall
from system.errors import StepFailed
from user.TerminalSteps import TerminalSteps


class TemplateDefinition:
    """tpl-T defined as bastion template defines it, on the switch's own network with its station's MAC."""

    def __init__(self, access):
        self.access = access

    def make_disk_and_define(self, template):
        """make-disk T first, when it has not run already in this bastion template."""
        call = StepCall()
        call.step = "make-disk"
        call.arguments = [template.word]
        try:
            TerminalSteps(self.access.privileged_steps).run(call)
        except StepFailed:
            print(f"{self.access.configuration.command}: make-disk failed (lines above).")
            return
        self.define(template)

    def define(self, template):
        configuration = self.access.configuration
        libvirt = self.access.libvirt.open()
        threads = HostThreads(HostReading(libvirt, self.access.files, configuration.images_folder).read())
        content = self.access.live_data_file.read()
        request = DefinitionRequest(name=template.name, memory=template.memory, vcpus=template.vcpus, disk=template.file,
                                    win11=template.win11, uuid=template.uuid, mac=content.stations[template.name].mac,
                                    iso=template.iso)
        request.pins = threads.pins(template.vcpus, DenseFirst(), {}).threads
        root = WindowsDefinition(configuration, threads).root(request)
        CableEdit(configuration.switch).set_lane(root, content, configuration.switch)
        libvirt.define(DefinitionFragments().text(root))
        self.access.changes.add(template.name)
        print(f"{template.name} is defined.")

    access = None
