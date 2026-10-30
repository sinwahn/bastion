from user.HostLines import HostLines
from user.Question import Choice


class GraphicsChoices:
    """The graphics a VM may get: emulated only, or emulated plus a card of the host; a card the host keeps is shown but cannot be picked."""

    def __init__(self, state, configuration):
        self.state = state
        self.configuration = configuration

    def choices(self, now):
        choices = [Choice("emulated", "emulated only (a window on the host)" + (" (now)" if now == "emulated" else ""))]
        for index, device in enumerate(self.state.devices):
            if device.passthrough:
                held = f"; held now by {', '.join(device.holders)}" if device.holders else ""
                choices.append(Choice(f"card{index}", f"emulated plus the {device.name} (one VM at a time; shown through looking-glass{held})"
                                      + (" (now)" if now == f"card{index}" else "")))
            else:
                choices.append(Choice(f"host{index}", HostLines(self.state, self.configuration).device(device), True))
        return choices

    def now(self, vm):
        """The pick vm's definition holds now."""
        now = "emulated"
        for index, device in enumerate(self.state.devices):
            if set(vm.hostdevs) & set(device.functions):
                now = f"card{index}"
        return now

    def functions(self, pick):
        if pick.startswith("card"):
            return self.state.devices[int(pick[4:])].functions
        return []

    def text(self, pick):
        if pick.startswith("card"):
            return f"emulated plus the {self.state.devices[int(pick[4:])].name}"
        return "emulated only"

    state = None
    configuration = None
