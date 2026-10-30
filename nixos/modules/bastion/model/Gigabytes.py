class Gigabytes:
    """Sizes as the screens write them: RAM comes in MiB, a disk in bytes, the host's share in GiB."""

    @staticmethod
    def of_mebibytes(mib):
        """MiB as GB (GiB) in plain words: 4096 -> '4', 1536 -> '1.5'."""
        gigabytes = mib / Gigabytes.kMibPerGib
        if gigabytes == int(gigabytes):
            return str(int(gigabytes))
        return f"{gigabytes:.1f}"

    @staticmethod
    def of_bytes(count):
        """Bytes as GB (GiB) with one decimal, rounded, as the exchange step writes them."""
        tenths = (count * 10 + Gigabytes.kGib // 2) // Gigabytes.kGib
        return f"{tenths // 10}.{tenths % 10} GB"

    kGib = 1024 ** 3
    kMibPerGib = 1024
    kUnitBytes = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3}
