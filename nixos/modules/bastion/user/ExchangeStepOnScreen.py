from system.errors import StepFailed
from user.ScreenSteps import ScreenSteps


class ExchangeStepOnScreen:
    """The exchange step (bastion.nix) run from the broker section, its output's lines and its error's text kept apart."""

    def __init__(self, app, access):
        self.app = app
        self.access = access

    def run(self, arguments):
        steps = ScreenSteps(self.app, self.access.privileged_steps)
        try:
            steps.run_apart(self.access.configuration.exchange.step, arguments)
        except StepFailed as failure:
            self.answer = failure.answer
            self.ended_well = False
            return
        self.answer = steps.last_answer()
        self.ended_well = True

    def ran_well(self):
        return self.ended_well

    def lines(self):
        return self.answer.lines

    def error(self):
        return self.answer.error

    def said(self):
        """What the step printed: its output's lines, then its error."""
        return "\n".join(self.answer.lines + ([self.answer.error] if self.answer.error else []))

    app = None
    access = None
    answer = None
    ended_well = False
