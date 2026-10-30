from user.ExchangeStepRun import ExchangeStepRun


class SendCommand:
    """bastion send FROM FILE TO (the word is the exchange's): one file from FROM's Outbox to TO's Inbox, or to the host's inbox, through broker-vm, by the exchange step."""

    def __init__(self, access):
        self.access = access
        self.step = ExchangeStepRun(access)

    def accepts(self, arguments):
        return len(arguments) == 4 and arguments[0] == self.access.configuration.exchange.send

    def run(self, arguments):
        self.step.run(arguments)

    def exit_code(self):
        return self.step.exit_code()

    access = None
    step = None
