from system.PrivilegedSteps import StepAnswer


class TerminalSteps:
    """bastion.nix's privileged steps run from the command line, on the terminal as it is."""

    def __init__(self, steps):
        self.steps = steps

    def run(self, call):
        if call.feeds:
            self.steps.run_attached_feeding(call.step, call.arguments, call.sent)
        else:
            self.steps.run_attached(call.step, call.arguments)
        return StepAnswer()

    steps = None
