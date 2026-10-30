import xml.etree.ElementTree as ET

from model.CableEdit import CableEdit
from model.DefinitionEdit import DefinitionEdit
from model.DefinitionFragments import DefinitionFragments


class VmStart:
    """A VM started pinned to the threads picked now, with the vsock device of the number picked now, for this start only."""

    # That definition is saved, the VM started, and the definition it had
    # before saved again, so its pins read back its preference, a running VM
    # keeps the live ones and its vsock device, and the stored definition
    # holds no vsock device once the start is made.

    def __init__(self, libvirt, threads, switch):
        self.libvirt = libvirt
        self.threads = threads
        self.switch = switch

    def start(self, name, plan, start):
        before = self.libvirt.definition_text(name)
        root = ET.fromstring(before)
        edit = DefinitionEdit(self.threads)
        edit.set_pins(root, plan.pins)
        edit.set_vsock(root, plan.vsock)
        start.change(root, CableEdit(self.switch))
        self.libvirt.define(self.kFragments.text(root))
        try:
            self.libvirt.create(name)
        finally:
            self.libvirt.define(before)

    libvirt = None
    threads = None
    switch = ""
    kFragments = DefinitionFragments()
