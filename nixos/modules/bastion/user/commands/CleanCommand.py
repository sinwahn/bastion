from user.ExchangeStepRun import ExchangeStepRun


class CleanCommand:
    """bastion clean NAME (the word is the exchange's): NAME's kept copies in broker-vm deleted, and the files of NAME's stopped sends on the host, each logged first."""

    def __init__(self, access):
        self.access = access
        self.step = ExchangeStepRun(access)

    def accepts(self, arguments):
        return len(arguments) == 2 and arguments[0] == self.access.configuration.exchange.clean

    def run(self, arguments):
        self.step.run(arguments)

    def exit_code(self):
        return self.step.exit_code()

    access = None
    step = None
