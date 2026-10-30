from system.enums import WaitSeconds
from system.errors import ShellCommandFailed


class ServiceUnits:
    """The host's systemd units, read with systemctl as the user."""

    def __init__(self, shell, systemctl, log):
        self.shell = shell
        self.systemctl = systemctl
        self.log = log

    def is_active(self, unit):
        try:
            answer = self.shell.read([self.systemctl, "is-active", unit], WaitSeconds.kCommand)
        except ShellCommandFailed as failure:
            self.log.note(f"{unit} counts as not active: systemctl did not answer ({failure})")
            return False
        return answer.stdout.strip() == "active"

    shell = None
    systemctl = ""
    log = None
