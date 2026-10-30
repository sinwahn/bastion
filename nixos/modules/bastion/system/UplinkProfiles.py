from system.enums import WaitSeconds
from system.errors import ShellCommandFailed


class UplinkProfiles:
    """NetworkManager's connection profiles of the uplinks, read with nmcli as the user."""

    def __init__(self, shell, nmcli):
        self.shell = shell
        self.nmcli = nmcli

    def active_names(self):
        answer = self._read("-g", "NAME", "connection", "show", "--active")
        if answer.returncode:
            raise ShellCommandFailed(f"NetworkManager refuses the read: {answer.stderr.strip()}")
        return set(answer.stdout.splitlines())

    def autoconnect(self, name):
        return self._value("connection.autoconnect", name)

    def route_metric(self, name):
        return self._value("ipv4.route-metric", name)

    def never_default(self, name):
        return self._value("ipv4.never-default", name)

    def _value(self, field, name):
        answer = self._read("-g", field, "connection", "show", name)
        if answer.returncode == 0:
            return answer.stdout.strip()
        return ""

    def _read(self, *arguments):
        return self.shell.read([self.nmcli, *arguments], WaitSeconds.kCommand)

    shell = None
    nmcli = ""
