import urllib.error
import urllib.request


class HostInternet:
    """The host's own internet, as gate checks it: any answer from the address within the time gate gives."""

    def __init__(self, target, seconds, log):
        self.target = target
        self.seconds = seconds
        self.log = log

    def answers(self):
        try:
            urllib.request.urlopen(self.target, timeout=self.seconds).close()
            return True
        except urllib.error.HTTPError:
            return True
        except Exception as error:
            if isinstance(error, MemoryError):
                raise
            self.log.note(f"{self.target} gives no answer: {error}")
            return False

    target = ""
    seconds = 0
    log = None
