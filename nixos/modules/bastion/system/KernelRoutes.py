from system.enums import WaitSeconds


class KernelRoutes:
    """The host's default routes, read with ip as the user."""

    def __init__(self, shell, ip):
        self.shell = shell
        self.ip = ip

    def default_device(self):
        """The device of the default route with the lowest metric; empty when there is none."""
        answer = self.shell.read([self.ip, "-4", "route", "show", "default"], WaitSeconds.kCommand)
        best_metric = 0
        best_device = self.kNoDevice
        for line in answer.stdout.splitlines():
            words = line.split()
            device = self._word_after(words, "dev")
            metric = int(self._word_after(words, "metric") or 0)
            if device and (not best_device or metric < best_metric):
                best_metric = metric
                best_device = device
        return best_device

    def _word_after(self, words, key):
        if key in words[:-1]:
            return words[words.index(key) + 1]
        return ""

    shell = None
    ip = ""
    kNoDevice = ""
