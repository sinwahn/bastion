import dataclasses


@dataclasses.dataclass
class SharedMemory:
    path: str = ""
    size: int = 0


class SharedMemoryDevice:
    """kvmfr's device and the size of its shared memory, read from the host."""

    def __init__(self, files, log):
        self.files = files
        self.log = log

    def read(self):
        """The first kvmfr device and its size; an empty one when the host has none."""
        memory = SharedMemory()
        paths = self.files.matching(self.kDevices)
        if not paths:
            self.log.note("no kvmfr device on the host: looking-glass's shared memory is not there")
            return memory
        memory.path = paths[0]
        memory.size = self.files.device_answer(paths[0], self.kDmabufGetSize)
        return memory

    files = None
    log = None
    kDevices = "/dev/kvmfr[0-9]*"
    # kvmfr's ioctl that answers the size of its shared memory:
    # _IO('u', 0x44) (module/kvmfr.h), _IO(type, nr) = type << 8 | nr (the
    # kernel's include/uapi/asm-generic/ioctl.h, no size, no direction).
    kDmabufGetSize = (ord("u") << 8) | 0x44
