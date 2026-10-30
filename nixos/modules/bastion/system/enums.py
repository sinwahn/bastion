import enum


class LinuxKeyCode(enum.IntEnum):
    # The Space key in libvirt's Linux key codes, the code set virsh send-key
    # uses by default (keycodemapdb 22b8996 data/keymaps.csv 118, libvirt
    # v12.2.0's subprojects/keycodemapdb; tools/virsh-domain.c 9078-9079).
    kSpace = 57


class WaitSeconds(enum.IntEnum):
    kCommand = 10
    kVmPoll = 5
    kKeyPress = 1
