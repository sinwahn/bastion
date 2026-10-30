class DisplayModes:
    """The screen sizes the Looking Glass display driver takes in a shared memory, by the driver's own rule."""

    def fitting(self, memory):
        """Each size of the driver's list, in its order, that fits a shared memory of memory bytes, as WIDTHxHEIGHT."""
        return [f"{width}x{height}" for width, height in self.kDriverList if self._fits(width, height, memory)]

    def _fits(self, width, height, memory):
        # gnif/LookingGlass at cdba29f2f6bcae3ded26369fc231a067cbca3752,
        # idd/LGIdd/transport/lgmp/CLGMPFrameCaps.cpp 28-57 and 80-111: a row
        # of the frame is 4 bytes a pixel (28), rounded up to the row
        # alignment; each of the frame buffers takes the frame and one
        # placement alignment, rounded up to it; the buffers begin at the
        # frames' start rounded up to it; all of it within the memory less its
        # recovery region at the end (idd/LGIdd/transport/lgmp/CIVSHMEM.h
        # 52-58).
        frame = -(-width * self.kPixelBytes // self.kRowAlignment) * self.kRowAlignment * height
        buffer = -(-(frame + self.kPlacementAlignment) // self.kPlacementAlignment) * self.kPlacementAlignment
        start = -(-self.kFramesStart // self.kPlacementAlignment) * self.kPlacementAlignment
        return start + self.kFrameBuffers * buffer <= memory - self.kRecoveryRegion

    kPixelBytes = 4
    # D3D12_TEXTURE_DATA_PITCH_ALIGNMENT and
    # D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT, Microsoft's d3d12.h
    # (microsoft/DirectX-Headers at 461ef5138bd30922b44fbad77c4e47662812d2d5,
    # include/directx/d3d12.h 1464 and 928).
    kRowAlignment = 256
    kPlacementAlignment = 65536
    # LGMP_Q_FRAME_BUFFER_LEN (gnif/LGProtocol at
    # 62b52724b63b6e179b8fb7e0c7c03e9a8b4e1636, LookingGlass's
    # repos/LGProtocol, include/LGProtocol/LGMPConfig.h 32), the count the
    # driver hands the rule (CLGMPFrameTransport.cpp 253-258).
    kFrameBuffers = 3
    # KVMFR_R_REGION_SIZE (LGProtocol's include/LGProtocol/KVMFRRecovery.h 31).
    kRecoveryRegion = 65536
    # Where the driver's frame buffers begin in the shared memory: the bytes
    # LGMP has handed out before them, which the driver reads at its start
    # inside Windows (idd/LGIdd/transport/lgmp/CLGMPFrameTransport.cpp
    # 124-128, the usable size less what LGMP has left) and the rule rounds
    # up to 65536 (CLGMPFrameCaps.cpp 96-98). The host cannot read it; it is
    # the sum below, in the order CLGMPTransport.cpp 86-101 lays it out. LGMP
    # is gnif/LGMP at 10e3fef41de71d5ecb4fe34e4a6aa721a86df84d and LGProtocol
    # gnif/LGProtocol at 62b52724b63b6e179b8fb7e0c7c03e9a8b4e1636,
    # LookingGlass's repos/LGMP and repos/LGProtocol; the other paths are
    # LookingGlass's, idd/LGIdd/transport/lgmp/ for the C++ files.
    # - 9728 + udata, rounded up to 4: LGMP's header, 6 queue headers of 1600
    #   bytes with it (LGMP lgmp/src/host.c 109-120, lgmp/src/headers.h 297 and
    #   340, lgmp/include/lgmp/lgmp.h 30); udata the KVMFR records with the CPU
    #   model's and the Windows edition's names (CLGMPHost.cpp 41-132).
    # - 192: the frame queue and its 2 owner queues, 2 messages of 32 bytes
    #   each, every queue's ring 64-byte aligned (CLGMPFrameTransport.cpp 50-55
    #   and 85-122; LGProtocol LGMPConfig.h 31; LGMP host.c 177-179 and
    #   217-218, headers.h 277).
    # - 1024: the pointer queue, 32 messages (CLGMPControl.cpp 36-41 and 54-60;
    #   LGMPConfig.h 33).
    # - 896: 32 pointer positions of a KVMFRCursor, 28 bytes by its fields
    #   (CLGMPControl.cpp 32-33 and 62-72; LGProtocol KVMFR.h 167-179), every
    #   allocation rounded up to 4 (LGMP host.c 424-427 and 436-468).
    # - 3145812: 3 pointer shapes of 28 + 512 x 512 x 4 bytes (CLGMPControl.cpp
    #   30-31 and 74-84, CLGMPControl.h 43).
    # - 196860: 3 colour transforms of 28 + 65592 bytes, a KVMFRColorTransform's
    #   flags, 3 x 4 matrix, scalar and 4096 x 4 table of 4-byte numbers
    #   (CLGMPControl.cpp 86-98, CLGMPControl.h 44; LGProtocol KVMFRTypes.h 57
    #   and 77-84).
    # - 128: the input queue, 4 messages (CLGMPInputTransport.cpp 44-49 and
    #   102-109; LGMPConfig.h 34).
    # - 133120: 8 input streams of 256 + 128 x 128 bytes, each 64-byte aligned
    #   (CLGMPInputTransport.cpp 111-129, CLGMPInputTransport.h 77-78;
    #   LGProtocol KVMFRInput.h 30-32; LGMP lgmp/src/stream.c 154-173 and 704,
    #   lgmp/src/stream.h 30, 110 and 114).
    # - 1792: 4 input status blocks of 448 bytes (CLGMPInputTransport.cpp
    #   132-142, CLGMPInputTransport.h 76; LGProtocol KVMFRInput.h 193).
    # - 1024: the clipboard queue, 32 messages (CLGMPClipboardTransport.cpp
    #   52-57 and 151-158; LGMPConfig.h 35).
    # - 768: 4 clipboard status blocks of 128 bytes and 4 messages of 64
    #   (CLGMPClipboardTransport.cpp 160-174, CLGMPClipboardTransport.h 44-45;
    #   LGProtocol KVMFRClipboard.h 29, 355 and 363).
    # - 2098688: 2 clipboard streams of 256 + 4 x 262272 bytes, 64 + 262208
    #   rounded up to 64 (CLGMPClipboardTransport.cpp 202-235,
    #   CLGMPClipboardTransport.h 56-57; LGProtocol KVMFRClipboard.h 29 and 42;
    #   LGMP stream.c 154-173).
    # Together 5590080 + udata, which stays far below 46016 bytes, so the
    # start is 86 x 65536 = 5636096 for this driver build, the one
    # presets/win/README.txt names (build B7-829-cdba29f2).
    kFramesStart = 5636096
    # The Looking Glass display driver's default list, in its order
    # (idd/LGCommon/DefaultDisplayModes.h 23-35).
    kDriverList = (
        (7680, 4800), (7680, 4320), (6016, 3384), (5760, 3600), (5760, 3240), (5120, 2800),
        (4096, 2560), (4096, 2304), (3840, 2400), (3840, 2160), (3200, 2400), (3200, 1800),
        (3008, 1692), (2880, 1800), (2880, 1620), (2560, 1600), (2560, 1440), (1920, 1440),
        (1920, 1200), (1920, 1080), (1600, 1200), (1600, 1024), (1600, 1050), (1600, 900),
        (1440, 900), (1400, 1050), (1366, 768), (1360, 768), (1280, 1024), (1280, 960),
        (1280, 800), (1280, 768), (1280, 720), (1280, 600), (1152, 864), (1024, 768),
        (800, 600), (640, 480),
    )
