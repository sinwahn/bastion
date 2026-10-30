import os
import xml.etree.ElementTree as ET

from system.errors import FileFailed


class CopyFolder:
    """The copy folder (bastion.nix's copyDir): each VM's definition, the copy of the live data file and the saved state."""

    def __init__(self, files, folder, log):
        self.files = files
        self.folder = folder
        self.log = log

    def make(self):
        self.files.make_folders(self.folder)

    def write(self, name, body):
        self.files.write_whole_utf8(os.path.join(self.folder, name), body)

    def saved_live_data_or_empty(self):
        path = os.path.join(self.folder, self.kLiveDataName)
        if not self.files.exists(path):
            self.log.note(f"{path} is not there: the copy starts empty")
            return {}
        return self.files.read_json_utf8(path)

    def saved_live_data(self):
        return self.files.read_json_utf8(os.path.join(self.folder, self.kLiveDataName))

    def saved_names(self):
        """The VMs saved as NAME.xml, by name."""
        if not self.files.is_folder(self.folder):
            self.log.note(f"{self.folder} is not there: no VM is saved")
            return []
        return sorted(entry[:-len(".xml")] for entry in self.files.list_folder(self.folder) if entry.endswith(".xml"))

    def saved_definition(self, name):
        return self.files.read_text_utf8(os.path.join(self.folder, name + ".xml"))

    def saved_uuid(self, definition):
        try:
            return ET.fromstring(definition).findtext("uuid") or ""
        except ET.ParseError as error:
            raise FileFailed(str(error)) from error

    def state_folder(self, name):
        return os.path.join(self.folder, "state", name)

    def has_state(self, name):
        return self.files.is_folder(self.state_folder(name))

    def has_tpm_state(self, name, uuid):
        return self.files.is_folder(os.path.join(self.state_folder(name), uuid))

    files = None
    folder = ""
    log = None
    kLiveDataName = "networks.json"
