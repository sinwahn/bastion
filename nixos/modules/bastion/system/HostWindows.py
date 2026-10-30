class HostWindows:
    """The windows a VM shows on the host: virt-manager's console and the looking-glass client."""

    def __init__(self, shell, uri):
        self.shell = shell
        self.uri = uri

    def open_console(self, name):
        # The virt-manager console of any VM, in a session of its own and not
        # waited for: virt-manager 5.1.0 stays in the foreground unless told
        # to fork (virtManager/virtmanager.py 118-137, its options --connect
        # 153 and --show-domain-console 178).
        self.shell.start_detached(["virt-manager", "--connect", self.uri, "--show-domain-console", name])

    def open_glass(self, command):
        self.shell.start_detached(command)

    def start_glass(self, command):
        return self.shell.start_window(command)

    def close_glass(self, window):
        self.shell.stop_window(window)

    shell = None
    uri = ""
