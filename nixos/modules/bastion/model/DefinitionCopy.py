from model.NetworksCopy import NetworksCopy
from model.errors import CopyNotWritten, FileNotDone, Refused
from system.errors import FileFailed, LibvirtCallFailed


class DefinitionCopy:
    """The copy in the copy folder, after a change of this run, written as the user."""

    # Each VM's inactive definition as NAME.xml, read through libvirt, for
    # every VM libvirt holds that Nix does not define; and networks.json, the
    # live file plus the stations the copy held for VMs not defined now, left
    # as it is when the live file cannot be read. Each file is written whole
    # beside itself and moved into place; nothing in the folder is removed.

    def __init__(self, access):
        self.access = access

    def write(self):
        changes = self.access.changes
        if not changes.any():
            return
        changes.clear()
        try:
            self._write_files()
        except (LibvirtCallFailed, FileFailed) as error:
            raise CopyNotWritten(f"the copy in {self.access.configuration.copy_folder} is not written: {error}") from error

    def _write_files(self):
        libvirt = self.access.libvirt.open()
        nix_names = self.access.nix_domains.names()
        names = libvirt.domain_names()
        bodies = {name + ".xml": libvirt.definition_text(name) for name in names if name not in nix_names}
        live_data = self._live_data_copy(set(names))
        if live_data:
            bodies["networks.json"] = live_data
        folder = self.access.copy_folder
        folder.make()
        for name, body in bodies.items():
            folder.write(name, body)

    def _live_data_copy(self, defined):
        # Empty when the live file cannot be read: the copy's networks.json is
        # then left as it is.
        live_data_file = self.access.live_data_file
        try:
            live = live_data_file.read_checked()
        except (FileNotDone, Refused) as error:
            self.access.log.note(f"the copy of networks.json is left as it is: {error}")
            return ""
        old = self.access.live_format.parse(self.access.copy_folder.saved_live_data_or_empty())
        return self.access.live_format.render(NetworksCopy().copied(live, old, defined))

    access = None
