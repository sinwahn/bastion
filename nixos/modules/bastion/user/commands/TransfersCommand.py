from user.ExchangeStepRun import ExchangeStepRun


class TransfersCommand:
    """bastion transfers [NAME] (the word is the exchange's): broker-vm's log, all of it or the lines naming NAME."""

    def __init__(self, access):
        self.access = access
        self.step = ExchangeStepRun(access)

    def accepts(self, arguments):
        return 1 <= len(arguments) <= 2 and arguments[0] == self.access.configuration.exchange.transfers

    def run(self, arguments):
        self.step.run([self.access.configuration.exchange.transfers, "", *arguments[1:]])

    def exit_code(self):
        return self.step.exit_code()

    access = None
    step = None
