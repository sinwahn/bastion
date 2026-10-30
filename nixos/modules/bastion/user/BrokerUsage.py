from model.Gigabytes import Gigabytes
from user.ExchangeStepOnScreen import ExchangeStepOnScreen
from user.ServiceLines import ServiceLines


class BrokerUsage:
    """The broker section's first line: while broker-vm runs, the settings' line usage with the figures of the exchange step's usage, in GB with one decimal; else broker-vm's WRONG line."""

    # When the figures cannot be read, broker-vm's line, and what the step
    # said below it.

    def __init__(self, app, access):
        self.app = app
        self.access = access

    def read(self):
        configuration = self.access.configuration
        service = next(service for service in configuration.service_vms if service.name == configuration.broker_vm)
        self.said = []
        if not self.access.service_units.is_active(service.unit):
            self.text = "WRONG: " + ServiceLines().wrong(service)
            return
        self.text = f"{service.name}: running"
        self._read_figures()

    def line(self):
        return self.text

    def messages(self):
        """What the screen says below: the step's error, or all it said when the figures cannot be read."""
        return self.said

    def _read_figures(self):
        exchange = self.access.configuration.exchange
        step = ExchangeStepOnScreen(self.app, self.access)
        step.run([exchange.usage_verb])
        figures = next((words for words in (line.split(", ") for line in step.lines())
                        if len(words) == 3 and all(word.isdigit() for word in words)), [])
        if not (step.ran_well() and figures):
            self.said = [step.said()]
            return
        used, size, limit = (int(figure) for figure in figures)
        self.text = self._filled(exchange.usage_line, {"broker": self.access.configuration.broker_vm,
                                                       "used": Gigabytes.of_bytes(used), "size": Gigabytes.of_bytes(size),
                                                       "limit": Gigabytes.of_bytes(limit)})
        if step.error():
            self.said = [step.error()]

    def _filled(self, line, fields):
        # Each {NAME} replaced by its value, as the exchange step fills the
        # settings' exchange lines.
        for name, value in fields.items():
            line = line.replace("{" + name + "}", str(value))
        return line

    app = None
    access = None
    text = ""
    said = ()
