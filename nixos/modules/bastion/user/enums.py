import enum


class ExitCode(enum.IntEnum):
    kDone = 0
    kStopped = 1


class TemplateWait(enum.IntEnum):
    # Space pressed once a second for 30 seconds for "Press any key to boot
    # from CD or DVD", after 5 seconds for the console to open.
    kConsoleSeconds = 5
    kKeyPresses = 30
    # More than 6000000 KiB is an installed Windows.
    kInstalledKib = 6000000
