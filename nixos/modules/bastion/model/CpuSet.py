class CpuSet:
    """libvirt's cpu lists."""

    @staticmethod
    def parse(text):
        """'0-3,12-15' -> [0, 1, 2, 3, 12, 13, 14, 15]."""
        threads = []
        for part in text.split(","):
            part = part.strip()
            if not part:
                continue
            if "-" in part:
                first, last = part.split("-", 1)
                threads.extend(range(int(first), int(last) + 1))
            else:
                threads.append(int(part))
        return threads

    @staticmethod
    def format(threads):
        """[0, 1, 2, 12] -> '0-2,12'."""
        runs = []
        for thread in sorted(set(threads)):
            if runs and thread == runs[-1][-1] + 1:
                runs[-1].append(thread)
            else:
                runs.append([thread])
        return ",".join(f"{run[0]}-{run[-1]}" if len(run) > 1 else str(run[0]) for run in runs)
