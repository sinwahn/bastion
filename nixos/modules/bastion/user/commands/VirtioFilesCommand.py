import os

from user.enums import ExitCode
from user.errors import Stop


class VirtioFilesCommand:
    """bastion virtio-files DIR: DIR/virtio made, holding the settings' store folder of the virtio driver folders whole."""

    # bastion.nix's virtioDrivers: the folders for the devices the tool's
    # definitions give, copied file by file without the store's read-only
    # modes so the copy can be removed, as exchange-files copies the viosock
    # folder. presets/attach.sh puts DIR's content onto the stick, where the
    # presets module repair installs them. A missing store folder stops it,
    # nothing made; nothing is printed when it is done.

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.kWord

    def run(self, arguments):
        store = self.access.configuration.virtio_drivers_folder
        if not self.access.files.is_folder(store):
            raise Stop(f"STOP: {store} is not there: the drivers come with the rebuild.")
        self.access.stick_files.copy_store_folder(store, os.path.join(arguments[1], self.kFolder))

    def exit_code(self):
        return ExitCode.kDone

    access = None
    kWord = "virtio-files"
    kFolder = "virtio"
