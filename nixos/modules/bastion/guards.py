# /etc/nixos/modules/bastion/guards.py
# The bastion tool's guards: plain functions, no libvirt and no screen, so
# they run anywhere. The figures they use are read from the host and from
# bastion.nix by bastion.py and handed in.
#   starts  a start is refused while the running VMs together would pass the
#         host; each VM is offered at most what the host has less its share
#         and less the service VMs.
#   disks  every VM's full disk size counts as taken.
#   cores  the cores
#         a VM is pinned to when it starts: a fast-first VM takes the fast
#         cores first and shares them with other fast-first VMs; any other
#         VM takes free dense cores first, then free fast cores, and shares
#         a core only when none is free.
# The networks section's checks and figures: a new network's name, lane and
# range.
# The looking-glass section's check: whether a screen size fits the shared
# memory, by the Looking Glass display driver's own rule.
# The copy and restore: the copy of networks.json, and networks.json after a
# restore.
# Units: RAM in MiB, disk in bytes, the host's share in threads and GiB.

import copy
import ipaddress
import re

GIB = 1024 ** 3
MIB_PER_GIB = 1024
UNIT_BYTES = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3}


def gb(mib):
    """MiB as GB (GiB) in plain words: 4096 -> '4', 1536 -> '1.5'."""
    g = mib / MIB_PER_GIB
    return str(int(g)) if g == int(g) else f"{g:.1f}"


def parse_cpuset(text):
    """libvirt's cpu list: '0-3,12-15' -> [0, 1, 2, 3, 12, 13, 14, 15]."""
    out = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def format_cpuset(threads):
    """[0, 1, 2, 12] -> '0-2,12'."""
    out = []
    run = []
    for t in sorted(set(threads)):
        if run and t == run[-1] + 1:
            run.append(t)
            continue
        if run:
            out.append(f"{run[0]}-{run[-1]}" if len(run) > 1 else str(run[0]))
        run = [t]
    if run:
        out.append(f"{run[0]}-{run[-1]}" if len(run) > 1 else str(run[0]))
    return ",".join(out)


def cores_and_kinds(siblings, banks):
    """The host's cores and the kind of each thread.
    siblings: {thread: [the threads of its core]}, from the capabilities'
    topology; banks: the level 3 cache banks [{"cpus": [...], "size": bytes}].
    A core is a thread with its siblings, ordered by its first thread. The
    fast kind is the bank with the most cache per thread; the others are
    dense. Returns (cores, {thread: "fast" or "dense"})."""
    cores = sorted({tuple(sorted(s)) for s in siblings.values()})
    rated = [(b["size"] / len(b["cpus"]), b) for b in banks if b["cpus"]]
    best = max((r for r, _ in rated), default=None)
    kind = {t: "dense" for c in cores for t in c}
    for r, b in rated:
        for t in b["cpus"]:
            kind[t] = "fast" if r == best else "dense"
    return cores, kind


def held(running, services):
    """What the running VMs and the service VMs hold: (threads, RAM MiB)."""
    return (sum(v["vcpus"] for v in running) + sum(s["vcpu"] for s in services),
            sum(v["memory"] for v in running) + sum(s["mem"] for s in services))


def start_refusals(host, share, services, running, vm):
    """The reasons vm may not start now; an empty list lets it start.
    host {"threads", "ram"}; share {"threads", "ram" (GiB)}; services: the
    service VMs {"name", "vcpu", "mem"}; running: the running VMs
    {"name", "vcpus", "memory"}; vm {"name", "vcpus", "memory"}."""
    others = [v for v in running if v["name"] != vm["name"]]
    threads, ram = held(others, services)
    reasons = []
    free_t = host["threads"] - share["threads"] - threads
    if vm["vcpus"] > free_t:
        who = ", ".join([f'{s["name"]} {s["vcpu"]}' for s in services]
                        + [f'{v["name"]} {v["vcpus"]}' for v in others])
        reasons.append(f'{vm["name"]} needs {vm["vcpus"]} threads and {max(free_t, 0)} are free: '
                       f'the host has {host["threads"]}, {share["threads"]} stay for the host, '
                       f'running now: {who}.')
    free_m = host["ram"] - share["ram"] * MIB_PER_GIB - ram
    if vm["memory"] > free_m:
        who = ", ".join([f'{s["name"]} {gb(s["mem"])}' for s in services]
                        + [f'{v["name"]} {gb(v["memory"])}' for v in others])
        reasons.append(f'{vm["name"]} needs {gb(vm["memory"])} GB of RAM and {gb(max(free_m, 0))} GB are free: '
                       f'the host has {gb(host["ram"])}, {share["ram"]} stay for the host, '
                       f'running now (GB): {who}.')
    return reasons


def core_offers(host, share, services, threads_per_core):
    """The thread counts a VM may be given, in whole cores."""
    top = host["threads"] - share["threads"] - sum(s["vcpu"] for s in services)
    return list(range(threads_per_core, top + 1, threads_per_core))


def ram_offers(host, share, services, step):
    """The RAM sizes a VM may be given, in GiB, in steps."""
    top = host["ram"] - share["ram"] * MIB_PER_GIB - sum(s["mem"] for s in services)
    return list(range(step, top // MIB_PER_GIB + 1, step))


def disk_room(free, share, disks):
    """The bytes still free for VM disks: the host's free space, less
    the host's share, less what every VM's disk may still grow by.
    disks: [{"capacity", "allocation"}] of every defined VM."""
    promised = sum(max(d["capacity"] - d["allocation"], 0) for d in disks)
    return free - share["disk"] * GIB - promised


def new_disk_offers(start_gib, room, step):
    """The sizes (GiB) of a new disk, from the template's size in
    steps, each counted whole."""
    out = []
    g = start_gib
    while g * GIB <= room:
        out.append(g)
        g += step
    return out


def grow_offers(current_gib, room, step):
    """The bigger sizes (GiB) of a disk now current_gib; what it grows
    by must fit the room (its own promise is already counted there)."""
    out = []
    g = current_gib + step
    while (g - current_gib) * GIB <= room:
        out.append(g)
        g += step
    return out


def pins_at_start(cores, kind, vcpus, fast_first, taken):
    """The threads a VM's vcpus are pinned to when it starts, whole cores at
    a time, and the running VMs it shares a core with.
    taken: {thread: [names of running VMs pinned there]}. A core is free
    when no running VM is pinned to any of its threads."""
    fast = [c for c in cores if kind[c[0]] == "fast"]
    dense = [c for c in cores if kind[c[0]] != "fast"]

    def free(c):
        return not any(t in taken for t in c)

    if fast_first:
        order = ([c for c in fast if free(c)] + [c for c in fast if not free(c)]
                 + [c for c in dense if free(c)] + [c for c in dense if not free(c)])
    else:
        order = ([c for c in dense if free(c)] + [c for c in fast if free(c)]
                 + [c for c in dense if not free(c)] + [c for c in fast if not free(c)])
    threads = [t for c in order for t in c][:vcpus]
    shared = sorted({n for t in threads for n in taken.get(t, [])})
    return threads, shared


def kinds_of(threads, kind):
    """Which kind of cores a VM got: '8 fast' or '4 dense + 2 fast'."""
    counts = {}
    for t in threads:
        counts[kind.get(t, "dense")] = counts.get(kind.get(t, "dense"), 0) + 1
    return " + ".join(f"{n} {k}" for k, n in counts.items()) or "none pinned"


def fast_first_of(pins, kind):
    """The VM's preference, read back from the first pin of its definition."""
    return bool(pins) and kind.get(pins[0]) == "fast"


def name_refusal(name, used, retired, name_max, prefixes):
    """The reason a new VM's name is refused, or None. The name is also its
    cable's name on the switch."""
    if not re.fullmatch(r"[A-Za-z0-9-]+", name):
        return "letters, digits and dashes only."
    if len(name) > name_max:
        return f"at most {name_max} characters: the name is also the VM's cable."
    for p in prefixes:
        if name.startswith(p):
            return f"a name starting with {p} is libvirt's own for cables."
    if name in used:
        return f"{name} is already used."
    if name in retired:
        return f"a retired VM has this name; its disk and definition are kept in retired/{name}."
    return None


def next_address(ip_range, taken):
    """The first free address of a network's range, or None."""
    for a in ipaddress.ip_network(ip_range, strict=False).hosts():
        if str(a) not in taken:
            return str(a)
    return None


def first_address(ip_range):
    """The first address of a network's range: firewall-vm's on that network."""
    return str(next(ipaddress.ip_network(ip_range, strict=False).hosts()))


# The loopback inside every Linux system, firewall-vm's too: the kernel
# gives it this fixed name (drivers/net/loopback.c).
LOOPBACK = "lo"


def network_refusal(name, networks, host_names, name_max, firewall_vm):
    """The reason a new network's name is refused, or None. The name is also
    firewall-vm's leg on that network, so it may not be a name of
    host-networks.nix (host_names: its switches, VMs and cables) nor the
    loopback inside firewall-vm."""
    if not re.fullmatch(r"[A-Za-z0-9-]+", name):
        return "letters, digits and dashes only."
    if len(name) > name_max:
        return f"at most {name_max} characters: the name is also {firewall_vm}'s leg."
    if name in networks:
        return f"{name} is already a network."
    if name in host_names:
        return f"{name} is a name of host-networks.nix (a switch, a service VM or a cable)."
    if name == LOOPBACK:
        return f"{name} is {firewall_vm}'s loopback."
    return None


def next_lane(networks):
    """A new network's lane: one above the highest lane among networks."""
    return max(n["lane"] for n in networks.values()) + 1


def next_range(networks, home):
    """A new network's range: the /24 whose third octet is one above the
    highest third octet among networks' ranges, in the same /16 as the range
    of the network home."""
    top = max(ipaddress.ip_network(n["ip-range"], strict=False).network_address.packed[2]
              for n in networks.values())
    a, b = ipaddress.ip_network(networks[home]["ip-range"], strict=False).network_address.packed[:2]
    return f"{a}.{b}.{top + 1}.0/24"


def copy_networks(live, old, defined):
    """The copy of networks.json: the live file, plus each station the old
    copy holds for a VM that is not defined now (defined: the names of every
    VM libvirt holds) with the network it names, taken from the old copy.
    Such a station is the copy's own even when the live file holds that
    name, since no VM stands behind the live entry; a VM defined now gets
    the live entry, and a network the live file holds keeps the live
    entry."""
    out = copy.deepcopy(live)
    for name, st in old.get("stations", {}).items():
        if name in defined:
            continue
        out["stations"][name] = copy.deepcopy(st)
        network = st.get("network")
        if network not in out["networks"] and network in old.get("networks", {}):
            out["networks"][network] = copy.deepcopy(old["networks"][network])
    return out


def restore_networks(live, saved, names):
    """networks.json after the VMs names are restored: each one's station
    from the copy (saved) in place of a live entry of the same name, since
    no VM stands behind that entry; the network it names added from the copy
    when the live file lacks it, a network the live file holds kept as it
    is; every other station kept as it is. Returns the new file, the names
    of the stations taken from the copy and of the networks added."""
    out = copy.deepcopy(live)
    stations, networks = [], []
    for name in names:
        st = saved.get("stations", {}).get(name)
        if st is None:
            continue
        out["stations"][name] = copy.deepcopy(st)
        stations.append(name)
        network = st.get("network")
        if network not in out["networks"] and network in saved.get("networks", {}):
            out["networks"][network] = copy.deepcopy(saved["networks"][network])
            networks.append(network)
    return out, stations, networks


def idd_fits(width, height, memory, start):
    """True when the Looking Glass display driver takes the screen size
    width x height in a shared memory of memory bytes whose frame buffers
    begin at start (bastion.py's IDD_FRAMES_START), by the driver's own rule
    (gnif/LookingGlass at cdba29f2f6bcae3ded26369fc231a067cbca3752,
    idd/LGIdd/transport/lgmp/CLGMPFrameCaps.cpp 28-57 and 80-111): a row of
    the frame is 4 bytes a pixel (28), rounded up to the row alignment; each
    of the frame buffers takes the frame and one placement alignment, rounded
    up to it; the buffers begin at start rounded up to it; all of it within
    the memory less its recovery region at the end
    (idd/LGIdd/transport/lgmp/CIVSHMEM.h 52-58).
    The row alignment and the placement alignment are
    D3D12_TEXTURE_DATA_PITCH_ALIGNMENT and
    D3D12_DEFAULT_RESOURCE_PLACEMENT_ALIGNMENT, Microsoft's d3d12.h
    (microsoft/DirectX-Headers at 461ef5138bd30922b44fbad77c4e47662812d2d5,
    include/directx/d3d12.h 1464 and 928); the frame buffers are
    LGMP_Q_FRAME_BUFFER_LEN (gnif/LGProtocol at
    62b52724b63b6e179b8fb7e0c7c03e9a8b4e1636, LookingGlass's
    repos/LGProtocol, include/LGProtocol/LGMPConfig.h 32), the count the
    driver hands the rule (CLGMPFrameTransport.cpp 253-258); the recovery
    region is KVMFR_R_REGION_SIZE (LGProtocol's
    include/LGProtocol/KVMFRRecovery.h 31)."""
    pixel, row_align, place_align, buffers, recovery = 4, 256, 65536, 3, 65536
    frame = -(-width * pixel // row_align) * row_align * height
    buffer = -(-(frame + place_align) // place_align) * place_align
    return -(-start // place_align) * place_align + buffers * buffer <= memory - recovery
