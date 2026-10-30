class HelpText:
    """The command line's help, printed when its words name no command."""

    def __init__(self, access):
        self.access = access

    def print_lines(self):
        command = self.access.configuration.command
        exchange = self.access.configuration.exchange
        names = self.access.templates.words()
        print(f"{command}, the status screen, then the VMs, the networks, the devices, looking-glass and "
              f"{exchange.section}\n"
              f"{command} list, every VM and template, its state, its disk, its card\n"
              f"{command} template T, Windows Setup in the template tpl-T (T: {names})\n"
              f"{command} seal T, after Sysprep: tpl-T sealed, {command} makes VMs from it\n"
              f"{command} first NAME, the first start of NAME, without network\n"
              f"{command} start NAME, starts NAME and shows it\n"
              f"{command} console NAME, the console window of NAME\n"
              f"{command} resolution NAME, the size NAME's Windows is locked at, or follows\n"
              f"{command} {exchange.exchange_files} DIR, the files the presets module {exchange.module} sets the "
              f"exchange up with, into DIR/{exchange.module}\n"
              f"{command} virtio-files DIR, the virtio driver folders the presets module repair installs, "
              "into DIR/virtio\n"
              f"{command} {exchange.send} FROM FILE TO\n"
              f"{command} {exchange.transfers} [NAME]\n"
              f"{command} {exchange.clean} NAME\n"
              f"{command} template, first and start run until the VM is off, meanwhile the host does not go "
              "to sleep by itself. Never close the lid then.")

    access = None
