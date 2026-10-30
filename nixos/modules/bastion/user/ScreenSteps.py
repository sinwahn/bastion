class ScreenSteps:
    """bastion.nix's privileged steps run from the screens: the terminal given back while one runs, so sudo can ask there."""

    def __init__(self, app, steps):
        self.app = app
        self.steps = steps

    def run(self, call):
        """The step's output and errors as one text."""
        with self.app.suspend():
            print(call.note or f"{call.step} runs (sudo may ask your password) ...", flush=True)
            if call.feeds:
                return self.steps.run_captured_feeding(call.step, call.arguments, call.sent)
            return self.steps.run_captured(call.step, call.arguments)

    def run_apart(self, step, arguments):
        """The step's output lines and its error text apart."""
        with self.app.suspend():
            print(f"{step} runs (sudo may ask your password) ...", flush=True)
            return self.steps.run_apart(step, arguments)

    app = None
    steps = None
