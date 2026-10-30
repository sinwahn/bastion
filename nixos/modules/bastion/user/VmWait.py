import signal
import sys
import time

from system.SleepHold import SleepHold
from system.enums import WaitSeconds
from user.enums import ExitCode


class VmWait:
    """The wait of the command line's template, start and first: sleep held off while the VM runs, libvirt asked every 5 seconds."""

    # Once the VM no longer runs, the window and the hold are closed, also
    # when the wait is ended by a signal.

    def __init__(self, access, libvirt):
        self.access = access
        self.libvirt = libvirt

    def wait(self, name):
        self._hold_sleep_while(name, self._watch)

    def wait_showing_glass(self, name, command):
        """The wait with the looking-glass window of command open."""
        self.glass_command = command
        self._hold_sleep_while(name, self._watch_beside_glass)

    def _hold_sleep_while(self, name, watching):
        for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            signal.signal(number, self._end_on_signal)
        hold = SleepHold(self.access.shell)
        hold.take(name)
        try:
            watching(name)
        finally:
            hold.release()

    def _watch_beside_glass(self, name):
        self.access.windows.start_glass(self.glass_command)
        try:
            self._watch(name)
        finally:
            self.access.windows.close_glass()

    def _watch(self, name):
        print(f"{name} runs. {self.kLidWarning}", flush=True)
        while self.libvirt.state_word(name) == self.libvirt.kRunningWord:
            time.sleep(WaitSeconds.kVmPoll)
        print(f"{name} is off.", flush=True)

    def _end_on_signal(self, number, frame):
        sys.exit(ExitCode.kStopped)

    access = None
    libvirt = None
    glass_command = ()
    # The sentence a VM's start ends with, after "NAME runs": the wait prints
    # it, and the start screen says it.
    kLidWarning = "Never close the lid while it runs. Shut Windows down to end it."
