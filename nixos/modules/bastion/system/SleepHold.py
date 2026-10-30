class SleepHold:
    """Sleep held off while a VM runs, until this process ends however it ends."""

    # systemd-inhibit holds its lock while its command, cat, reads a pipe from
    # this process (systemd v260.5 src/login/inhibit.c 334-373: the lock
    # taken, the command run, the lock held until it ends; --what, --who and
    # --why 188-193).

    def __init__(self, shell):
        self.shell = shell

    def take(self, name):
        self.shell.start_hold(["systemd-inhibit", "--what=sleep:idle", f"--who={name}", f"--why={name} runs", "cat"])

    def release(self):
        self.shell.release_hold()

    shell = None
