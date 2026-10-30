import os

from user.enums import ExitCode
from user.errors import Stop


class ExchangeFilesCommand:
    """bastion exchange-files DIR (the word is the exchange's): the files the presets module of the exchange sets Windows up with, in DIR's folder named by the module's word."""

    # The settings' store folder of the viosock files whole, copied file by
    # file without the store's read-only modes so the copy can be removed;
    # the exchange key's public half, the key's file name and .pub (OpenSSH
    # V_10_5_P1 ssh-keygen.1 218-222) in the folder of networks.json, where
    # broker-vm's key unit copies it; and the words file MODULE.json, every
    # word the module reads: the group's account, folder, inbox-folder,
    # outbox-folder, bridge-folder and module-lines under the same keys, the
    # command's name as command and the public half's file name as
    # public-key. presets/attach.sh puts DIR's content onto the stick. A
    # missing public half stops it, nothing made; nothing is printed when it
    # is done.

    def __init__(self, access):
        self.access = access

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.access.configuration.exchange.exchange_files

    def run(self, arguments):
        configuration = self.access.configuration
        exchange = configuration.exchange
        public_key = os.path.basename(exchange.key) + ".pub"
        public_path = os.path.join(os.path.dirname(configuration.live_data_file), public_key)
        if not self.access.files.is_file(public_path):
            raise Stop(f"STOP: {public_path} is not there: the keys are made at {configuration.broker_vm}'s first start.")
        folder = os.path.join(arguments[1], exchange.module)
        stick = self.access.stick_files
        stick.copy_store_folder(configuration.viosock_folder, folder)
        stick.copy_file(public_path, folder)
        words = dict(exchange.module_words)
        words["command"] = configuration.command
        words["public-key"] = public_key
        stick.write_words(os.path.join(folder, exchange.module + ".json"), words)

    def exit_code(self):
        return ExitCode.kDone

    access = None
