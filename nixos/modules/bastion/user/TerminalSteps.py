class TerminalSteps:
    """bastion.nix's privileged steps run from the command line, on the terminal as it is."""

    def __init__(self, steps):
        self.steps = steps

    def run(self, call):
        self.steps.run_attached(call.step, call.arguments)

    def run_feeding(self, call):
        self.steps.run_attached_feeding(call.step, call.arguments, call.sent)

    def last_answer(self):
        return self.steps.last_answer()

    steps = None
