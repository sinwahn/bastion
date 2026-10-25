# /etc/nixos/modules/bastion/bastion.py
# The bastion tool (the command "bastion", modules/bastion/bastion.nix): a status
# screen first, then the sections VMs, networks, devices, looking-glass and
# the broker.
# The VMs live in libvirt's own store; each network, and each VM's network,
# address, internet rule, locked screen size and list of the VMs it may send
# files to (the broker section; its key in networks.json and the section's
# words are host-networks.nix's exchange, handed over in the settings), live
# in the live data file networks.json. The looking-glass window's settings
# live in the client's per-user file. A VM's
# cable is on the switch in every case; on a network other than the switch's
# own it holds that network's lane as a vlan tag, and its port is isolated
# unless the network's reach-each-other is true. Every figure is read from the
# host, from libvirt or from the settings bastion.nix hands over (the first
# argument, a JSON file). The networks section's path check reads, beside the
# host, the two answer points inside the service VMs over vsock.
#   bastion: the screens
#   bastion list: every VM that is not a template, its state, its
#     disk and its card, then each template
#   bastion template T: Windows Setup in the template tpl-T: its Windows .iso
#     copied in place from ~/Downloads when it is not
#     there, tpl-T defined when it is not, its console, its
#     start with Space pressed for the CD prompt, the wait
#   bastion seal T: after Sysprep: the checks, tpl-T's sealed mark
#     written, tpl-T undefined keeping its firmware
#     variables and TPM state
#   bastion start NAME: starts NAME pinned to free cores of its kind, with a
#     vsock device for that start only, as the start screen does, opens its
#     window and waits
#   bastion first NAME: the same, with its link down for that start: no
#     network, and its console
#   bastion console NAME: the console of any VM
#   bastion resolution NAME: the screen size NAME's Windows is locked at,
#     WIDTHxHEIGHT, or follows; presets/attach.sh asks it
#   bastion exchange-files DIR (the word is host-networks.nix's exchange's
#     exchange-files): the files the presets module of the exchange sets
#     Windows up with, in DIR's folder named by the module's word: the
#     viosock folders, the exchange key's public half and the words file;
#     presets/attach.sh puts them onto the stick
#   bastion send FROM FILE TO (the words of this command and the next two
#     are host-networks.nix's exchange's send, transfers and clean): one
#     file from FROM's Outbox to TO's Inbox, or to the host's inbox when TO
#     is the host's name, through broker-vm, by the exchange step
#   bastion transfers [NAME]: broker-vm's log, all of it or the lines
#     naming NAME
#   bastion clean NAME: NAME's kept copies in broker-vm deleted, and the
#     files of NAME's stopped sends on the host, each logged first
# The wait holds sleep off until the VM is off; the start screen runs it as a
# process of its own, bastion start or bastion first of the VM it started.
# The steps that need root (networks-write, disk-grow, disk-retire,
# make-disk, template-seal, state-copy and the exchange step, named by
# host-networks.nix's exchange's step) are bastion.nix's programs, run
# through sudo.
# After every change it makes, the tool writes the copy into the copy folder
# (bastion.nix's copyDir, ~/presets/bastion): each VM's definition and the
# copy of networks.json (write_copy). The VMs section's "copy firmware and
# TPM" copies each VM's firmware variables and TPM state into its state
# folder through state-copy; its "restore" brings saved VMs back.
# The command's name, which the help and the messages print, is the
# settings' command (bastion.nix).

import glob
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import types
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

import guards
from guards import GIB, MIB_PER_GIB, UNIT_BYTES, gb

import libvirt
from rich.text import Text
from textual import work
from textual.app import App
from textual.binding import Binding
from textual.screen import Screen
from textual.widgets import DataTable, Footer, Header, Input, OptionList, SelectionList, Static, TextArea
from textual.widgets.option_list import Option
from textual.widgets.selection_list import Selection

QEMU_NS = "http://libvirt.org/schemas/domain/qemu/1.0"
ET.register_namespace("qemu", QEMU_NS)

# A display device: the PCI base class of the kernel's header
# include/linux/pci_ids.h (PCI_BASE_CLASS_DISPLAY), the class's top byte.
PCI_BASE_CLASS_DISPLAY = 0x03
# kvmfr's ioctl that answers the size of its shared memory:
# _IO('u', 0x44) (module/kvmfr.h), _IO(type, nr) = type << 8 | nr (the
# kernel's include/uapi/asm-generic/ioctl.h, no size, no direction).
KVMFR_DMABUF_GETSIZE = (ord("u") << 8) | 0x44

# The looking-glass client the host runs is gnif/LookingGlass at
# cdba29f2f6bcae3ded26369fc231a067cbca3752 (modules/host/looking-glass.nix);
# the lines below name its files. It reads /etc's file first; the per-user
# file (glass_file) is read later and overrides it (client/src/config.c
# 572-623).
GLASS_ETC_FILE = "/etc/looking-glass-client.ini"
# The key names the client accepts for its release key input:escapeKey, its
# table linux_to_str (client/src/kb.c 192-358), in the table's order.
# KEY_RESERVED, index 0, is left out: no key sends it, so the capture would
# have no release key.
GLASS_KEYS = (
    "KEY_ESC", "KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5", "KEY_6", "KEY_7", "KEY_8", "KEY_9",
    "KEY_0", "KEY_MINUS", "KEY_EQUAL", "KEY_BACKSPACE", "KEY_TAB", "KEY_Q", "KEY_W", "KEY_E",
    "KEY_R", "KEY_T", "KEY_Y", "KEY_U", "KEY_I", "KEY_O", "KEY_P", "KEY_LEFTBRACE",
    "KEY_RIGHTBRACE", "KEY_ENTER", "KEY_LEFTCTRL", "KEY_A", "KEY_S", "KEY_D", "KEY_F", "KEY_G",
    "KEY_H", "KEY_J", "KEY_K", "KEY_L", "KEY_SEMICOLON", "KEY_APOSTROPHE", "KEY_GRAVE",
    "KEY_LEFTSHIFT", "KEY_BACKSLASH", "KEY_Z", "KEY_X", "KEY_C", "KEY_V", "KEY_B", "KEY_N", "KEY_M",
    "KEY_COMMA", "KEY_DOT", "KEY_SLASH", "KEY_RIGHTSHIFT", "KEY_KPASTERISK", "KEY_LEFTALT",
    "KEY_SPACE", "KEY_CAPSLOCK", "KEY_F1", "KEY_F2", "KEY_F3", "KEY_F4", "KEY_F5", "KEY_F6",
    "KEY_F7", "KEY_F8", "KEY_F9", "KEY_F10", "KEY_NUMLOCK", "KEY_SCROLLLOCK", "KEY_KP7", "KEY_KP8",
    "KEY_KP9", "KEY_KPMINUS", "KEY_KP4", "KEY_KP5", "KEY_KP6", "KEY_KPPLUS", "KEY_KP1", "KEY_KP2",
    "KEY_KP3", "KEY_KP0", "KEY_KPDOT", "KEY_102ND", "KEY_F11", "KEY_F12", "KEY_RO", "KEY_HENKAN",
    "KEY_KATAKANAHIRAGANA", "KEY_MUHENKAN", "KEY_KPENTER", "KEY_RIGHTCTRL", "KEY_KPSLASH",
    "KEY_SYSRQ", "KEY_RIGHTALT", "KEY_HOME", "KEY_UP", "KEY_PAGEUP", "KEY_LEFT", "KEY_RIGHT",
    "KEY_END", "KEY_DOWN", "KEY_PAGEDOWN", "KEY_INSERT", "KEY_DELETE", "KEY_KPEQUAL", "KEY_PAUSE",
    "KEY_KPCOMMA", "KEY_HANGEUL", "KEY_HANJA", "KEY_YEN", "KEY_LEFTMETA", "KEY_RIGHTMETA",
    "KEY_COMPOSE", "KEY_POWER", "KEY_F13", "KEY_F14", "KEY_F15", "KEY_F16", "KEY_F17", "KEY_F18",
    "KEY_F19", "KEY_F20", "KEY_F21", "KEY_F22", "KEY_F23", "KEY_F24", "KEY_OPEN", "KEY_HELP",
    "KEY_MENU", "KEY_FRONT", "KEY_AGAIN", "KEY_UNDO", "KEY_CUT", "KEY_COPY", "KEY_PASTE",
    "KEY_KPJPCOMMA", "KEY_KATAKANA", "KEY_HIRAGANA", "KEY_ZENKAKUHANKAKU", "KEY_KPLEFTPAREN",
    "KEY_KPRIGHTPAREN", "KEY_PRINT", "KEY_MUTE", "KEY_VOLUMEUP", "KEY_VOLUMEDOWN", "KEY_NEXTSONG",
    "KEY_PLAYPAUSE", "KEY_PREVIOUSSONG", "KEY_STOPCD", "KEY_EJECTCD", "KEY_WWW", "KEY_BACK",
    "KEY_FORWARD", "KEY_STOP", "KEY_FIND", "KEY_SCROLLUP", "KEY_SCROLLDOWN", "KEY_EDIT",
    "KEY_SLEEP", "KEY_SCREENLOCK", "KEY_REFRESH", "KEY_CALC",
)
# The window's settings the looking-glass section sets, each under its label:
# the client's section and option, the value the client takes when no file
# sets it, and the values offered. The release key is input:escapeKey,
# default KEY_SCROLLLOCK (client/src/config.c 352-363). Full screen is
# win:fullScreen, default no (config.c 194-201), a yes or no the client
# writes as yes or no (common/src/option.c 101-104).
GLASS_OPTIONS = {
    "release key": ("input", "escapeKey", "KEY_SCROLLLOCK", GLASS_KEYS),
    "full screen": ("win", "fullScreen", "no", ("yes", "no")),
}
# The screen sizes the looking-glass section offers for a VM's lock: the
# Looking Glass display driver's default list, in its order
# (idd/LGCommon/DefaultDisplayModes.h 23-35), each offered only when it fits
# the shared memory read from the host (guards.idd_fits).
IDD_MODES = (
    (7680, 4800), (7680, 4320), (6016, 3384), (5760, 3600), (5760, 3240), (5120, 2800),
    (4096, 2560), (4096, 2304), (3840, 2400), (3840, 2160), (3200, 2400), (3200, 1800),
    (3008, 1692), (2880, 1800), (2880, 1620), (2560, 1600), (2560, 1440), (1920, 1440),
    (1920, 1200), (1920, 1080), (1600, 1200), (1600, 1024), (1600, 1050), (1600, 900),
    (1440, 900), (1400, 1050), (1366, 768), (1360, 768), (1280, 1024), (1280, 960),
    (1280, 800), (1280, 768), (1280, 720), (1280, 600), (1152, 864), (1024, 768),
    (800, 600), (640, 480),
)
# Where the driver's frame buffers begin in the shared memory, the start of
# guards.idd_fits's rule: the bytes LGMP has handed out before them, which the
# driver reads at its start inside Windows (idd/LGIdd/transport/lgmp/
# CLGMPFrameTransport.cpp 124-128, the usable size less what LGMP has left)
# and the rule rounds up to 65536 (CLGMPFrameCaps.cpp 96-98). The host cannot
# read it; it is the sum below, in the order CLGMPTransport.cpp 86-101 lays it
# out. LGMP is gnif/LGMP at 10e3fef41de71d5ecb4fe34e4a6aa721a86df84d and
# LGProtocol gnif/LGProtocol at 62b52724b63b6e179b8fb7e0c7c03e9a8b4e1636,
# LookingGlass's repos/LGMP and repos/LGProtocol; the other paths are
# LookingGlass's, idd/LGIdd/transport/lgmp/ for the C++ files.
#   9728 + udata, rounded up to 4: LGMP's header, 6 queue headers of 1600
#     bytes with it (LGMP lgmp/src/host.c 109-120, lgmp/src/headers.h 297 and
#     340, lgmp/include/lgmp/lgmp.h 30); udata the KVMFR records with the CPU
#     model's and the Windows edition's names (CLGMPHost.cpp 41-132).
#   192: the frame queue and its 2 owner queues, 2 messages of 32 bytes each,
#     every queue's ring 64-byte aligned (CLGMPFrameTransport.cpp 50-55 and
#     85-122; LGProtocol LGMPConfig.h 31; LGMP host.c 177-179 and 217-218,
#     headers.h 277).
#   1024: the pointer queue, 32 messages (CLGMPControl.cpp 36-41 and 54-60;
#     LGMPConfig.h 33).
#   896: 32 pointer positions of a KVMFRCursor, 28 bytes by its fields
#     (CLGMPControl.cpp 32-33 and 62-72; LGProtocol KVMFR.h 167-179), every
#     allocation rounded up to 4 (LGMP host.c 424-427 and 436-468).
#   3145812: 3 pointer shapes of 28 + 512 x 512 x 4 bytes (CLGMPControl.cpp
#     30-31 and 74-84, CLGMPControl.h 43).
#   196860: 3 colour transforms of 28 + 65592 bytes, a KVMFRColorTransform's
#     flags, 3 x 4 matrix, scalar and 4096 x 4 table of 4-byte numbers
#     (CLGMPControl.cpp 86-98, CLGMPControl.h 44; LGProtocol KVMFRTypes.h
#     57 and 77-84).
#   128: the input queue, 4 messages (CLGMPInputTransport.cpp 44-49 and
#     102-109; LGMPConfig.h 34).
#   133120: 8 input streams of 256 + 128 x 128 bytes, each 64-byte aligned
#     (CLGMPInputTransport.cpp 111-129, CLGMPInputTransport.h 77-78;
#     LGProtocol KVMFRInput.h 30-32; LGMP lgmp/src/stream.c 154-173 and 704,
#     lgmp/src/stream.h 30, 110 and 114).
#   1792: 4 input status blocks of 448 bytes (CLGMPInputTransport.cpp 132-142,
#     CLGMPInputTransport.h 76; LGProtocol KVMFRInput.h 193).
#   1024: the clipboard queue, 32 messages (CLGMPClipboardTransport.cpp 52-57
#     and 151-158; LGMPConfig.h 35).
#   768: 4 clipboard status blocks of 128 bytes and 4 messages of 64
#     (CLGMPClipboardTransport.cpp 160-174, CLGMPClipboardTransport.h 44-45;
#     LGProtocol KVMFRClipboard.h 29, 355 and 363).
#   2098688: 2 clipboard streams of 256 + 4 x 262272 bytes, 64 + 262208
#     rounded up to 64 (CLGMPClipboardTransport.cpp 202-235,
#     CLGMPClipboardTransport.h 56-57; LGProtocol KVMFRClipboard.h 29 and 42;
#     LGMP stream.c 154-173).
# Together 5590080 + udata, which stays far below 46016 bytes, so the rule's
# start is 86 x 65536 = 5636096 for this driver build, the one
# presets/win/README.txt names (build B7-829-cdba29f2).
IDD_FRAMES_START = 5636096

# The words virsh prints for a VM's state (virsh domstate), by libvirt's
# state: libvirt v12.2.0 tools/virsh-domain-monitor.c 130-147 and 1323-1328,
# the states include/libvirt/libvirt-domain.h 58-66.
VIRSH_STATES = {
    libvirt.VIR_DOMAIN_NOSTATE: "no state", libvirt.VIR_DOMAIN_RUNNING: "running",
    libvirt.VIR_DOMAIN_BLOCKED: "idle", libvirt.VIR_DOMAIN_PAUSED: "paused",
    libvirt.VIR_DOMAIN_SHUTDOWN: "in shutdown", libvirt.VIR_DOMAIN_SHUTOFF: "shut off",
    libvirt.VIR_DOMAIN_CRASHED: "crashed", libvirt.VIR_DOMAIN_PMSUSPENDED: "pmsuspended",
}
# The Space key in libvirt's Linux key codes, the code set virsh send-key
# uses by default (keycodemapdb 22b8996 data/keymaps.csv 118, libvirt
# v12.2.0's subprojects/keycodemapdb; tools/virsh-domain.c 9078-9079).
KEY_SPACE = 57
# The sentence a VM's start ends with, after "NAME runs": the wait prints it
# (wait_off), and the start screen says it.
LID_WARNING = "Never close the lid while it runs. Shut Windows down to end it."

CFG = {}
# The VMs given their first start in this run of the tool: their window is
# the console, as bastion first shows it (no looking-glass host in Windows yet).
FIRST_STARTED = set()
# What this run changed since the copy was last written (write_copy): the
# names of the VMs defined, changed or undefined, and networks.json's path.
CHANGED = set()


def text(s):
    """Plain text for a widget: no markup is read from data."""
    return Text(str(s))


# ---------------------------------------------------------------- the host

def connect():
    return libvirt.open(CFG["uri"])


class Host:
    """The host's threads, RAM, cores and free disk, read live."""

    def __init__(self, conn):
        info = conn.getInfo()
        self.ram = info[1]
        caps = ET.fromstring(conn.getCapabilities())
        siblings = {}
        for c in caps.findall("./host/topology/cells/cell/cpus/cpu"):
            siblings[int(c.get("id"))] = guards.parse_cpuset(c.get("siblings") or c.get("id"))
        banks = [{"cpus": guards.parse_cpuset(b.get("cpus")),
                  "size": int(b.get("size")) * UNIT_BYTES.get(b.get("unit"), 1)}
                 for b in caps.findall("./host/cache/bank") if b.get("level") == "3"]
        self.threads = len(siblings) or info[2]
        self.cores, self.kind = guards.cores_and_kinds(siblings, banks)
        self.threads_per_core = max((len(c) for c in self.cores), default=1)
        st = os.statvfs(CFG["images"])
        self.free = st.f_bavail * st.f_frsize

    def count(self, kind):
        return sum(1 for k in self.kind.values() if k == kind)

    def dense_threads(self):
        return [t for c in self.cores if self.kind[c[0]] != "fast" for t in c]

    def load(self):
        return {"threads": self.threads, "ram": self.ram}


# ------------------------------------------------------- libvirt's store

def addr_of(a):
    return tuple(int(a.get(k), 16) for k in ("domain", "bus", "slot", "function"))


def addr_text(a):
    return f"{a[0]:04x}:{a[1]:02x}:{a[2]:02x}.{a[3]:x}"


def pci_hostdevs(root):
    return [addr_of(a) for a in root.findall("./devices/hostdev[@type='pci']/source/address")]


def first_pins(root):
    """Each vcpu's first pinned thread, in vcpu order."""
    pins = {}
    for p in root.findall("./cputune/vcpupin"):
        pins[int(p.get("vcpu"))] = guards.parse_cpuset(p.get("cpuset"))
    return [pins[k][0] for k in sorted(pins) if pins[k]]


def all_pins(root):
    out = []
    for p in root.findall("./cputune/vcpupin"):
        out.extend(guards.parse_cpuset(p.get("cpuset")))
    return out


def memory_mib(el):
    return int(el.text) * UNIT_BYTES.get(el.get("unit", "KiB"), 1024) // UNIT_BYTES["MiB"]


def template_of(t):
    for p in CFG["templates"]:
        if p["t"] == t:
            return p
    return None


class Vm:
    """One VM of libvirt's store, read from its definition."""

    def __init__(self, dom, nets, nix):
        self.name = dom.name()
        self.root = ET.fromstring(dom.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE))
        self.active = bool(dom.isActive())
        live = ET.fromstring(dom.XMLDesc(0)) if self.active else self.root
        self.vcpus = int(self.root.findtext("vcpu"))
        self.memory = memory_mib(self.root.find("memory"))
        disk = self.root.find("./devices/disk[@device='disk']")
        self.disk_file = disk.find("source").get("file") if disk is not None else None
        self.disk_target = disk.find("target").get("dev") if disk is not None else None
        if self.disk_target:
            info = dom.blockInfo(self.disk_target)
            self.capacity, self.allocation = info[0], info[1]
        else:
            self.capacity = self.allocation = 0
        self.hostdevs = pci_hostdevs(self.root)
        self.live_hostdevs = pci_hostdevs(live)
        # glass on: the definition holds the looking-glass block (set_glass).
        self.glass = self.root.find(f"{{{QEMU_NS}}}commandline") is not None
        self.pins = first_pins(self.root)
        self.live_pins = all_pins(live) if self.active else []
        vsock = live.find("./devices/vsock/cid") if self.active else None
        self.live_vsock = int(vsock.get("address")) if vsock is not None else None
        self.station = nets.get("stations", {}).get(self.name)
        self.template = any(p["name"] == self.name for p in CFG["templates"])
        self.nix = self.name in nix

    def load(self):
        return {"name": self.name, "vcpus": self.vcpus, "memory": self.memory}

    def fast_first(self, host):
        return guards.fast_first_of(self.pins, host.kind)

    def graphics(self, devices):
        for d in devices:
            if set(self.hostdevs) & set(d["functions"]):
                return f"emulated + {d['name']}"
        return "emulated"

    def rule(self):
        if self.station is None:
            return "-"
        if self.station["rule"] == "listed":
            return f"listed ({len(self.station.get('names', []))} names)"
        return self.station["rule"]

    def row(self, devices):
        return [self.name, "running" if self.active else "off", str(self.vcpus),
                gb(self.memory) + " GB", str(self.capacity // GIB) + " GB",
                self.graphics(devices),
                self.station["network"] if self.station else "-", self.rule()]


def read_networks():
    with open(CFG["networksFile"]) as f:
        return json.load(f)


class Refused(ValueError):
    """A value of networks.json the checks refuse; restarting networks-apply
    would refuse it again."""


def read_networks_safe():
    """networks.json and None, or an empty one and the error: OSError or
    ValueError for a missing or unreadable file, Refused for a value."""
    try:
        nets = read_networks()
        for n, net in nets["networks"].items():
            if not isinstance(net.get("reach-each-other"), bool):
                raise Refused(f"network {n}: reach-each-other is not true or false")
        return nets, None
    except (OSError, ValueError) as e:
        return {"networks": {}, "stations": {}}, e


def nix_domains():
    """The domains Nix writes (a machine's own module may define VMs), such a
    VM rewritten by Nix at every boot: the <name> of each xml file one folder
    below /etc whose root
    element is a libvirt <domain>. A file that fails to parse is skipped.
    libvirt keeps its own definitions under /var/lib/libvirt, out of reach."""
    names = set()
    for path in glob.glob("/etc/*/*.xml"):
        try:
            root = ET.parse(path).getroot()
        except (ET.ParseError, OSError):
            continue
        if root.tag == "domain" and root.findtext("name"):
            names.add(root.findtext("name"))
    return names


def read_devices(conn, vms):
    """Every graphics device of the host, from libvirt's node devices. A
    device that is a hostdev in some VM's definition is held by one VM at a
    time, with the functions of its IOMMU group that definitions list; any
    other device is the host's."""
    listed = {a for v in vms for a in v.hostdevs}
    pci = {}
    for d in conn.listAllDevices(libvirt.VIR_CONNECT_LIST_NODE_DEVICES_CAP_PCI_DEV):
        x = ET.fromstring(d.XMLDesc(0))
        cap = x.find("./capability[@type='pci']")
        if cap is None:
            continue
        addr = tuple(int(cap.findtext(k)) for k in ("domain", "bus", "slot", "function"))
        product = cap.find("product")
        vendor = cap.find("vendor")
        name = (product.text if product is not None and product.text else "") or \
            f"{vendor.get('id') if vendor is not None else ''}:{product.get('id') if product is not None else ''}"
        pci[addr] = {"address": addr, "class": cap.findtext("class"),
                     "driver": x.findtext("./driver/name") or "", "name": name,
                     "group": [addr_of(a) for a in cap.findall("./iommuGroup/address")]}
    out = []
    for dev in sorted(pci.values(), key=lambda d: d["address"]):
        if not dev["class"] or int(dev["class"], 16) >> 16 != PCI_BASE_CLASS_DISPLAY:
            continue
        passthrough = dev["address"] in listed
        functions = []
        if passthrough:
            functions = [a for a in dev["group"] if a in listed] or [dev["address"]]
        holders = [v.name for v in vms if v.active and set(v.live_hostdevs) & set(functions)]
        out.append(dict(dev, passthrough=passthrough, functions=functions, holders=holders))
    return out


def device_line(d):
    where = f"{addr_text(d['address'])}, driver {d['driver'] or 'none'}"
    if d["passthrough"]:
        who = ", ".join(d["holders"]) if d["holders"] else "no VM"
        return f"{d['name']} ({where}): one VM at a time; held now by {who}"
    return f"{d['name']} ({where}): the host's; no VM uses it; Linux VMs come later"


def looking_glass():
    """kvmfr's device and the size of its shared memory, read from the host."""
    paths = sorted(glob.glob("/dev/kvmfr[0-9]*"))
    if not paths:
        return None
    import fcntl
    fd = os.open(paths[0], os.O_RDWR)
    try:
        size = fcntl.ioctl(fd, KVMFR_DMABUF_GETSIZE)
    finally:
        os.close(fd)
    return paths[0], size


def glass_file():
    """The looking-glass client's per-user file, by the client's rule:
    $XDG_CONFIG_HOME/looking-glass/client.ini, or
    ~/.config/looking-glass/client.ini when XDG_CONFIG_HOME is not set, home
    from HOME, else from the password entry (common/src/platform/linux/paths.c
    61-71, client/src/main.c 4310, client/src/config.c 607); expanduser takes
    home the same way."""
    base = os.environ.get("XDG_CONFIG_HOME")
    if base is None:
        base = os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "looking-glass", "client.ini")


def read_glass_file(path):
    """The options a looking-glass client file sets, {(section, option):
    value}, both names in lower case, read by the client's own rules
    (common/src/option.c 437-476, 507-686, 909): a line that begins with
    ";" is a comment, a line that begins with "[" opens the section named up
    to "]", an option's line is name=value with the spaces around both left
    out, names match in any case, and the last line of an option wins.
    Nothing when the file is not there."""
    out = {}
    try:
        with open(path, encoding="latin-1") as f:
            lines = f.read().split("\n")
    except FileNotFoundError:
        return out
    section = None
    for line in lines:
        if line.startswith(";"):
            continue
        if line.startswith("[") and "]" in line:
            section = line[1:line.index("]")].lower()
        elif section is not None and "=" in line:
            name, value = line.split("=", 1)
            out[(section, name.strip().lower())] = value.strip()
    return out


def glass_settings():
    """The window's settings as the client reads them, {label: value}: the
    per-user file's line, else /etc's file's, else the client's default. A
    key name is shown as the offered one it names in any case (client/src/
    config.c 958-979); full screen is yes for 1, on, yes or true in any case
    and no for any other value (common/src/option.c 64-72)."""
    etc = read_glass_file(GLASS_ETC_FILE)
    own = read_glass_file(glass_file())
    out = {}
    for label, (section, option, default, offered) in GLASS_OPTIONS.items():
        key = (section.lower(), option.lower())
        value = own.get(key, etc.get(key, default))
        if offered is GLASS_KEYS:
            value = next((k for k in GLASS_KEYS if k.lower() == value.lower()), value)
        else:
            value = "yes" if value.lower() in ("1", "on", "yes", "true") else "no"
        out[label] = value
    return out


def write_glass_option(section, option, value):
    """The option set to value in the per-user file: its line in its section
    replaced where it stands (the last one, which the client reads), else
    added after the section's last line, else the section and the line added
    at the end of the file. Every other line is kept as it is. The file is
    written whole beside itself and moved into place; its folder is made
    with mode 0700 when it is not there, as the client makes it
    (common/src/platform/linux/paths.c 78)."""
    path = glass_file()
    folder = os.path.dirname(path)
    try:
        with open(path, encoding="latin-1", newline="") as f:
            text_now = f.read()
    except FileNotFoundError:
        text_now = ""
    lines = text_now.split("\n")
    if lines[-1] == "":
        lines.pop()
    line = f"{option}={value}"
    here = None
    end = None
    section_now = None
    for i, old in enumerate(lines):
        if old.startswith("[") and "]" in old:
            section_now = old[1:old.index("]")].lower()
            if section_now == section.lower():
                end = i + 1
        elif section_now == section.lower() and old.strip():
            end = i + 1
            if not old.startswith(";") and "=" in old and \
                    old.split("=", 1)[0].strip().lower() == option.lower():
                here = i
    if here is not None:
        lines[here] = line
    elif end is not None:
        lines.insert(end, line)
    else:
        lines.extend(([""] if lines else []) + [f"[{section}]", line])
    os.makedirs(folder, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix="client.ini.")
    try:
        with os.fdopen(fd, "w", encoding="latin-1", newline="") as f:
            f.write("\n".join(lines) + "\n")
        if os.path.exists(path):
            shutil.copymode(path, tmp)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


class State:
    """What the screens show, read fresh from the host and libvirt."""

    def __init__(self):
        self.conn = connect()
        self.host = Host(self.conn)
        self.nets, self.nets_error = read_networks_safe()
        nix = nix_domains()
        self.vms = sorted((Vm(d, self.nets, nix) for d in self.conn.listAllDomains(0)), key=lambda v: v.name)
        self.devices = read_devices(self.conn, self.vms)

    def vm(self, name):
        for v in self.vms:
            if v.name == name:
                return v
        return None

    def running(self):
        return [v for v in self.vms if v.active]

    def taken(self, but=None):
        """{thread: [running VMs pinned there]}."""
        out = {}
        for v in self.running():
            if v.name != but:
                for t in v.live_pins:
                    out.setdefault(t, []).append(v.name)
        return out

    def room(self):
        return guards.disk_room(self.host.free, CFG["share"],
                                [{"capacity": v.capacity, "allocation": v.allocation} for v in self.vms])

    def holding(self):
        """The line above the cores and RAM screens."""
        svc = ", ".join(f"{s['name']} {s['vcpu']} and {gb(s['mem'])} GB" for s in CFG["services"])
        run = ", ".join(f"{v.name} holds {v.vcpus} and {gb(v.memory)} GB" for v in self.running()) or "no VM"
        sh = CFG["share"]
        return (f"the host has {self.host.threads} threads and {gb(self.host.ram)} GB of RAM; "
                f"{sh['threads']} threads and {sh['ram']} GB stay for the host; "
                f"the service VMs: {svc}; running now: {run}")


# ---------------------------------------------------- the domain's XML

def cputune_xml(pins, host):
    lines = [f"<vcpupin vcpu='{i}' cpuset='{t}'/>" for i, t in enumerate(pins)]
    dense = host.dense_threads()
    if dense:
        lines.append(f"<emulatorpin cpuset='{guards.format_cpuset(dense)}'/>")
    return "<cputune>" + "".join(lines) + "</cputune>"


def hostdev_xml(a):
    return ("<hostdev mode='subsystem' type='pci' managed='no'><source>"
            f"<address domain='0x{a[0]:04x}' bus='0x{a[1]:02x}' slot='0x{a[2]:02x}' function='0x{a[3]:x}'/>"
            "</source></hostdev>")


def commandline_xml(lg):
    path, size = lg
    return (f"<qemu:commandline xmlns:qemu='{QEMU_NS}'>"
            "<qemu:arg value='-device'/>"
            "<qemu:arg value=\"{'driver':'ivshmem-plain','id':'shmem0','memdev':'looking-glass'}\"/>"
            "<qemu:arg value='-object'/>"
            f"<qemu:arg value=\"{{'qom-type':'memory-backend-file','id':'looking-glass','mem-path':'{path}','size':{size},'share':true}}\"/>"
            "</qemu:commandline>")


def domain_xml(name, memory, vcpus, pins, host, disk, win11, functions=None, lg=None,
               uuid=None, mac=None, iso=None):
    """A Windows VM's definition; its cable's network part (vlan and port) is
    set_lane's."""
    tpc = host.threads_per_core
    card = bool(functions)
    w11 = "yes" if win11 else "no"
    cds = ""
    if iso:
        cds = (f"<disk type='file' device='cdrom'><driver name='qemu' type='raw'/><source file='{iso}'/>"
               "<target dev='sda' bus='sata'/><readonly/><boot order='2'/></disk>"
               f"<disk type='file' device='cdrom'><driver name='qemu' type='raw'/><source file='{CFG['virtioIso']}'/>"
               "<target dev='sdb' bus='sata'/><readonly/></disk>")
    return (
        f"<domain type='kvm' xmlns:qemu='{QEMU_NS}'>"
        f"<name>{name}</name>"
        + (f"<uuid>{uuid}</uuid>" if uuid else "")
        + f"<memory unit='MiB'>{memory}</memory><currentMemory unit='MiB'>{memory}</currentMemory>"
        f"<vcpu placement='static'>{vcpus}</vcpu>"
        + cputune_xml(pins, host)
        + "<os firmware='efi'><type arch='x86_64' machine='q35'>hvm</type><firmware>"
        f"<feature enabled='{w11}' name='secure-boot'/>"
        + ("<feature enabled='no' name='enrolled-keys'/>" if win11 else "")
        + "</firmware></os>"
        "<features><acpi/><apic/><hyperv mode='custom'><relaxed state='on'/><vapic state='on'/>"
        "<spinlocks state='on' retries='8191'/><vpindex state='on'/><synic state='on'/>"
        "<stimer state='on'/><frequencies state='on'/></hyperv>"
        + ("<smm state='on'/>" if win11 else "")
        + "</features>"
        "<cpu mode='host-passthrough' check='none' migratable='off'>"
        f"<topology sockets='1' dies='1' clusters='1' cores='{max(vcpus // tpc, 1)}' threads='{tpc}'/>"
        + ("<cache mode='passthrough'/>" if card else "")
        + "</cpu>"
        "<clock offset='localtime'><timer name='rtc' tickpolicy='catchup'/><timer name='pit' tickpolicy='delay'/>"
        "<timer name='hpet' present='no'/><timer name='hypervclock' present='yes'/></clock>"
        "<on_poweroff>destroy</on_poweroff><on_reboot>restart</on_reboot><on_crash>destroy</on_crash>"
        "<pm><suspend-to-mem enabled='no'/><suspend-to-disk enabled='no'/></pm>"
        "<devices>"
        f"<disk type='file' device='disk'><driver name='qemu' type='qcow2' discard='unmap'/>"
        f"<source file='{disk}'/><target dev='vda' bus='virtio'/><boot order='1'/></disk>"
        + cds
        + "<controller type='usb' model='qemu-xhci'/>"
        "<interface type='bridge'>"
        + (f"<mac address='{mac}'/>" if mac else "")
        + f"<source bridge='{CFG['switch']}'/><target dev='{name}'/><model type='virtio'/>"
        "</interface>"
        "<input type='tablet' bus='usb'/>"
        "<graphics type='spice' autoport='yes'><listen type='address' address='127.0.0.1'/>"
        "<clipboard copypaste='no'/><filetransfer enable='no'/></graphics>"
        "<video><model type='qxl'/></video><sound model='ich9'/><audio id='1' type='spice'/>"
        + ("<tpm model='tpm-crb'><backend type='emulator' version='2.0'/></tpm>" if win11 else "")
        + "<memballoon model='none'/>"
        + "".join(hostdev_xml(a) for a in (functions or []))
        + "</devices>"
        + (commandline_xml(lg) if card else "")
        + "</domain>")


def set_pins(root, pins, host):
    for ct in root.findall("cputune"):
        root.remove(ct)
    vcpu = root.find("vcpu")
    root.insert(list(root).index(vcpu) + 1, ET.fromstring(cputune_xml(pins, host)))


def set_vsock(root, number):
    """The VM's vsock device with the number given, in place of any vsock
    element the definition holds, since libvirt takes one only (libvirt
    v12.2.0 docs/formatdomain.rst 9425-9445, src/conf/domain_conf.c
    20583-20588); start_vm sets it for one start."""
    devices = root.find("devices")
    for old in devices.findall("vsock"):
        devices.remove(old)
    devices.append(ET.fromstring(f"<vsock model='virtio'><cid auto='no' address='{number}'/></vsock>"))


def set_cpu(root, vcpus, pins, host):
    root.find("vcpu").text = str(vcpus)
    set_pins(root, pins, host)
    topo = root.find("./cpu/topology")
    if topo is not None:
        topo.set("cores", str(max(vcpus // host.threads_per_core, 1)))
        topo.set("threads", str(host.threads_per_core))


def set_memory(root, mib):
    for tag in ("memory", "currentMemory"):
        el = root.find(tag)
        el.text = str(mib)
        el.set("unit", "MiB")


def set_glass(root, lg):
    """Glass off: every qemu:commandline element of the definition removed.
    Glass on, with lg (kvmfr's device and the size of its memory): the
    looking-glass block added again (commandline_xml)."""
    for c in root.findall(f"{{{QEMU_NS}}}commandline"):
        root.remove(c)
    if lg:
        root.append(ET.fromstring(commandline_xml(lg)))


def set_card(root, functions, lg):
    """The card given (functions) or taken; given, with the looking-glass
    block, so glass is on until it is turned off."""
    devices = root.find("devices")
    for h in devices.findall("hostdev"):
        if h.get("type") == "pci":
            devices.remove(h)
    cpu = root.find("cpu")
    for c in cpu.findall("cache"):
        cpu.remove(c)
    set_glass(root, lg if functions else None)
    if functions:
        for a in functions:
            devices.append(ET.fromstring(hostdev_xml(a)))
        cpu.append(ET.fromstring("<cache mode='passthrough'/>"))


def link_down(root):
    """The VM's cable on the switch starts with its link down."""
    for i in root.findall("./devices/interface"):
        src = i.find("source")
        if src is not None and src.get("bridge") == CFG["switch"]:
            for old in i.findall("link"):
                i.remove(old)
            i.append(ET.fromstring("<link state='down'/>"))


def set_lane(root, nets, network):
    """The VM's cable on the switch put on network: its lane as the vlan tag,
    or no vlan element for the switch's own network; and its port isolated
    unless the network's reach-each-other is true."""
    net = nets["networks"][network]
    for i in root.findall("./devices/interface"):
        src = i.find("source")
        if src is not None and src.get("bridge") == CFG["switch"]:
            for old in i.findall("vlan") + i.findall("port"):
                i.remove(old)
            if network != CFG["switch"]:
                i.append(ET.fromstring(f"<vlan><tag id='{net['lane']}'/></vlan>"))
            i.append(ET.fromstring(f"<port isolated='{'no' if net['reach-each-other'] else 'yes'}'/>"))


def network_of(root, nets):
    """The network the definition puts the VM's cable on: the network whose
    lane is its vlan tag, the switch's own network without one; None for a
    tag of no network in nets, or a VM with no cable on the switch."""
    for i in root.findall("./devices/interface"):
        src = i.find("source")
        if src is not None and src.get("bridge") == CFG["switch"]:
            tag = i.find("./vlan/tag")
            if tag is None:
                return CFG["switch"]
            for n, net in nets.get("networks", {}).items():
                if str(net["lane"]) == tag.get("id"):
                    return n
            return None
    return None


def xml_text(root):
    return ET.tostring(root, encoding="unicode")


def redefine(conn, name, change):
    """The definition changed by change(root), saved, and read back."""
    dom = conn.lookupByName(name)
    root = ET.fromstring(dom.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE))
    change(root)
    conn.defineXMLFlags(xml_text(root), libvirt.VIR_DOMAIN_DEFINE_VALIDATE)
    CHANGED.add(name)
    return ET.fromstring(conn.lookupByName(name).XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE))


def start_plan(s, v, first):
    """A start of v, for the start screen and for bastion start and bastion
    first: (the refusals, None, None, None), or ([], the pins, the lines that
    tell which cores it gets and whom it shares them with, its vsock number:
    the lowest from the settings' vsockFirst up that no running VM's live
    definition holds)."""
    h = s.host
    refusals = guards.start_refusals(h.load(), CFG["share"], CFG["services"],
                                     [x.load() for x in s.running()], v.load())
    for d in s.devices:
        if set(v.hostdevs) & set(d["functions"]) and d["holders"]:
            refusals.append(f"{d['holders'][0]} holds the {d['name']}. Shut it down first.")
    if refusals:
        return refusals, None, None, None
    fast = v.fast_first(h)
    taken = s.taken(v.name)
    pins, shared = guards.pins_at_start(h.cores, h.kind, v.vcpus, fast, taken)
    lines = [f"{v.name} starts on {v.vcpus} threads: {guards.kinds_of(pins, h.kind)}."]
    if shared:
        if fast and all(h.kind.get(t) == "fast" for t in pins if taken.get(t)):
            lines.append(f"It shares the fast cores with {', '.join(shared)}: fast-first VMs share them.")
        else:
            lines.append(f"No core is free for all its threads: it shares cores with {', '.join(shared)}.")
    if first:
        lines.append("This is its first start: its cable's link stays down, so it has no network this time.")
    held = {x.live_vsock for x in s.running()}
    number = CFG["vsockFirst"]
    while number in held:
        number += 1
    return [], pins, lines, number


def start_vm(conn, host, name, pins, vsock, first):
    """The VM pinned to the threads picked now, with the vsock device of the
    number picked now (set_vsock), and, at a first start, its link down, for
    this start only: that definition is saved, the VM started, and the
    definition it had before saved again, so its pins read back its
    preference, a running VM keeps the live ones and its vsock device, and
    the stored definition holds no vsock device once the start is made."""
    dom = conn.lookupByName(name)
    before = dom.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)
    root = ET.fromstring(before)
    set_pins(root, pins, host)
    set_vsock(root, vsock)
    if first:
        link_down(root)
    conn.defineXMLFlags(xml_text(root), libvirt.VIR_DOMAIN_DEFINE_VALIDATE)
    try:
        dom.create()
    finally:
        conn.defineXMLFlags(before, libvirt.VIR_DOMAIN_DEFINE_VALIDATE)


def open_console(name):
    """The virt-manager console of the VM name, of any VM, in a session of
    its own and not waited for: virt-manager 5.1.0 stays in the foreground
    unless told to fork (virtManager/virtmanager.py 118-137, its options
    --connect 153 and --show-domain-console 178)."""
    subprocess.Popen(["virt-manager", "--connect", CFG["uri"], "--show-domain-console", name],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def glass_command(vm):
    """The looking-glass client's command for vm: with win:setGuestRes=no
    when its station holds a resolution, so resizing the window never asks
    Windows to take its size (the option, client/src/config.c 218-224; the
    release key with = still asks, client/src/keybind.c 133-151; the command
    line's form section:name=value, doc/usage.rst 111-117; the client reads
    its command line after /etc's file and the per-user file, so it wins
    over both, config.c 625-627)."""
    if vm.station is not None and "resolution" in vm.station:
        return ["looking-glass-client", "win:setGuestRes=no"]
    return ["looking-glass-client"]


def open_window(vm):
    """looking-glass for a VM whose definition holds the looking-glass block,
    the console otherwise."""
    if vm.glass and vm.name not in FIRST_STARTED:
        subprocess.Popen(glass_command(vm), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    else:
        open_console(vm.name)


def vm_state(conn, name):
    """The VM's state in virsh's words, as virsh domstate prints it, or None
    when libvirt has no VM of that name (libvirt-python 12.2.0:
    virDomainGetState is the method state, libvirt-override.c 2705-2739,
    generator.py 1140-1142, an answer of None raised as libvirtError,
    generator.py 1659-1664)."""
    try:
        return VIRSH_STATES.get(conn.lookupByName(name).state(0)[0], VIRSH_STATES[libvirt.VIR_DOMAIN_NOSTATE])
    except libvirt.libvirtError:
        return None


def firewall_warning():
    """The line a start shows while firewall-vm does not run, else None."""
    fw = CFG["firewallVm"]
    unit = next(svc["unit"] for svc in CFG["services"] if svc["name"] == fw)
    return None if is_active(unit) else f"No internet for now: {fw} does not run (gate status)."


def wait_off(conn, name, glass):
    """The wait of bastion template, start and first: sleep held off while the
    VM name runs, by systemd-inhibit holding its lock while its command, cat,
    reads a pipe from this process, so the hold ends with this process
    however it ends (systemd v260.5 src/login/inhibit.c 334-373: the lock
    taken, the command run, the lock held until it ends; --what, --who and
    --why 188-193); with glass, the client's command (glass_command), the
    looking-glass window. libvirt is asked every 5 seconds; once the VM no
    longer runs, the window and the hold are closed, also when the wait is
    ended by a signal."""
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: sys.exit(1))
    hold = subprocess.Popen(["systemd-inhibit", "--what=sleep:idle", f"--who={name}", f"--why={name} runs", "cat"],
                            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    window = None
    try:
        if glass:
            window = subprocess.Popen(glass, stdin=subprocess.DEVNULL,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"{name} runs. {LID_WARNING}", flush=True)
        while vm_state(conn, name) == VIRSH_STATES[libvirt.VIR_DOMAIN_RUNNING]:
            time.sleep(5)
        print(f"{name} is off.", flush=True)
    finally:
        if window is not None:
            window.terminate()
        hold.stdin.close()
        hold.wait()
    return 0


def run_step(app, step, args, stdin=None, note=None):
    """A privileged step of bastion.nix through sudo; its answer back."""
    cmd = ["sudo", CFG["privileged"][step], *args]
    if app is None:
        return subprocess.run(cmd, input=stdin, text=True).returncode, ""
    with app.suspend():
        print(note or f"{step} runs (sudo may ask your password) ...", flush=True)
        r = subprocess.run(cmd, input=stdin, text=True, capture_output=True)
    return r.returncode, (r.stdout + r.stderr).strip()


def exchange_step(app, args):
    """The exchange step (bastion.nix) through sudo, as run_step runs a step
    with the screens, its standard output and its standard error apart:
    (its code, its output's lines, its error's text)."""
    step = CFG["exchange"]["step"]
    with app.suspend():
        print(f"{step} runs (sudo may ask your password) ...", flush=True)
        r = subprocess.run(["sudo", CFG["privileged"][step], *args], text=True, capture_output=True)
    return r.returncode, r.stdout.splitlines(), r.stderr.strip()


def fill(line, **fields):
    """A line of the settings' exchange lines with each {NAME} replaced by
    its value, as the exchange step fills them."""
    for name, value in fields.items():
        line = line.replace("{" + name + "}", str(value))
    return line


def gb_bytes(n):
    """Bytes as GB (GiB) with one decimal, rounded, as the exchange step
    writes them."""
    t = (n * 10 + GIB // 2) // GIB
    return f"{t // 10}.{t % 10} GB"


def write_networks(app, nets):
    answer = run_step(app, "networks-write", [], stdin=json.dumps(nets, indent=2) + "\n",
                      note="networks-write saves networks.json and applies it (sudo may ask your password) ...")
    CHANGED.add(CFG["networksFile"])
    return answer


def write_copy(app=None):
    """The copy, after a change of this run (CHANGED), in the copy folder
    (bastion.nix's copyDir), as the user: each VM's inactive definition as
    NAME.xml, read through libvirt, for every VM libvirt holds that Nix does
    not define; and networks.json, the live file plus the stations the copy
    held for VMs not defined now (guards.copy_networks), left as it is when
    the live file cannot be read. Each file is written whole beside itself
    and moved into place; nothing in the folder is removed. A failure is
    told on the screen, or printed."""
    if not CHANGED:
        return
    CHANGED.clear()
    folder = CFG["copyDir"]
    try:
        conn = connect()
        nix = nix_domains()
        doms = conn.listAllDomains(0)
        files = [(os.path.join(folder, d.name() + ".xml"), d.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE))
                 for d in doms if d.name() not in nix]
        nets, error = read_networks_safe()
        if error is None:
            path = os.path.join(folder, "networks.json")
            try:
                with open(path, encoding="utf-8") as f:
                    old = json.load(f)
            except FileNotFoundError:
                old = {}
            files.append((path, json.dumps(guards.copy_networks(nets, old, {d.name() for d in doms}),
                                           indent=2) + "\n"))
        os.makedirs(folder, exist_ok=True)
        for path, body in files:
            fd, tmp = tempfile.mkstemp(dir=folder, prefix=os.path.basename(path) + ".")
            try:
                with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
                    f.write(body)
                os.replace(tmp, path)
            except BaseException:
                os.unlink(tmp)
                raise
    except (libvirt.libvirtError, OSError, ValueError) as e:
        said = f"the copy in {folder} is not written: {e}"
        if app is None:
            print(said)
        else:
            app.notify(said)


def free_address(nets, network):
    """The next free address of network's range: never the range's first
    address (firewall-vm's on that network), the host's, or a station's."""
    r = nets["networks"][network]["ip-range"]
    taken = {st["ip"] for st in nets["stations"].values()} | {guards.first_address(r), CFG["hostAddress"]}
    return guards.next_address(r, taken)


def station_follows(app, v):
    """Before a start: when v's definition puts it on another network than
    its station's (a move saved while it ran), the station takes that
    network and its next free address, in one networks-write, whose (code,
    output) is returned; None when nothing changes."""
    if v.station is None:
        return None
    nets = read_networks()
    st = nets["stations"].get(v.name)
    to = network_of(v.root, nets)
    if st is None or to is None or st["network"] == to:
        return None
    st["network"] = to
    st["ip"] = free_address(nets, to)
    return write_networks(app, nets)


# ----------------------------------------------------- the status lines

def is_active(unit):
    try:
        r = subprocess.run([CFG["systemctl"], "is-active", unit], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() == "active"
    except (OSError, subprocess.SubprocessError):
        return False


def uplink_lines():
    """The host's uplinks as gate status reads them, without sudo; None when
    NetworkManager refuses the read."""
    def nm(*a):
        return subprocess.run([CFG["nmcli"], *a], capture_output=True, text=True, timeout=10)
    try:
        act = nm("-g", "NAME", "connection", "show", "--active")
        if act.returncode:
            return None
        active = set(act.stdout.splitlines())
        lines = []
        low = None
        preferred = CFG["prefer"]
        for u in CFG["uplinks"]:
            m = nm("-g", "ipv4.route-metric", "connection", "show", u["name"])
            if m.returncode == 0 and m.stdout.strip().lstrip("-").isdigit():
                if low is None or int(m.stdout.strip()) < low:
                    low = int(m.stdout.strip())
                    preferred = u["name"]
        for u in CFG["uplinks"]:
            nd = nm("-g", "ipv4.never-default", "connection", "show", u["name"])
            allowed = "allowed" if nd.returncode == 0 and nd.stdout.strip() == "no" else "not allowed"
            up = "up" if u["name"] in active else "not up"
            lines.append(f"{u['name']}: {up}, {allowed}" + (", preferred" if u["name"] == preferred else ""))
        r = subprocess.run([CFG["ip"], "-4", "route", "show", "default"], capture_output=True, text=True, timeout=10)
        best = None
        for line in r.stdout.splitlines():
            w = line.split()
            dev = w[w.index("dev") + 1] if "dev" in w[:-1] else None
            metric = int(w[w.index("metric") + 1]) if "metric" in w[:-1] else 0
            if dev and (best is None or metric < best[0]):
                best = (metric, dev)
        names = {u["device"]: u["name"] for u in CFG["uplinks"]}
        if best is None:
            route = "none"
        elif best[1] in names:
            route = names[best[1]]
        else:
            route = f"{best[1]}, not an uplink of uplinks.nix"
        lines.append(f"the host's route: {route}")
        return lines
    except (OSError, subprocess.SubprocessError):
        return None


def internet():
    """The host's own internet, as gate checks it: any answer from the
    address of host-networks.nix within the time gate gives."""
    try:
        urllib.request.urlopen(CFG["internet"], timeout=CFG["internetTimeout"]).close()
        return True
    except urllib.error.HTTPError:
        return True
    except Exception:
        return False


def service_wrong(svc):
    """A service VM's WRONG line while its unit is not active, as the status
    screen and the broker section show it."""
    return f"{svc['name']} is not running: {svc['meaning']}. Do: sudo systemctl start {svc['unit']}"


def status_text():
    wrong = []
    lines = []
    s = None
    try:
        s = State()
    except libvirt.libvirtError as e:
        wrong.append(f"libvirt cannot be read ({e}): no VM can be shown or started. "
                     "Do: sudo systemctl start libvirtd")
    if s:
        names = [v.name for v in s.vms if not v.template]
        tpl = ", ".join(f"{p['t']} {'sealed' if os.path.exists(p['sealed']) else 'not sealed'}"
                        for p in CFG["templates"])
        running = ", ".join(v.name for v in s.running()) or "none"
        lines.append(f"VMs: {len(names)}, templates: {tpl}; running: {running}")
        for v in s.vms:
            if v.nix:
                lines.append(f"{v.name}: defined by Nix, which rewrites it at every boot")
        h = s.host
        lines.append(f"host: {h.threads} threads ({h.count('fast')} fast, {h.count('dense')} dense), "
                     f"{gb(h.ram)} GB RAM, {h.free // GIB} GB free on the disk, "
                     f"{max(s.room(), 0) // GIB} GB of it free for VM disks")
        if isinstance(s.nets_error, Refused):
            wrong.append(f"networks.json cannot be read ({s.nets_error}): new VMs get no address "
                         "and no internet rule can change")
        elif s.nets_error:
            wrong.append(f"networks.json cannot be read ({s.nets_error}): new VMs get no address "
                         "and no internet rule can change. Do: sudo systemctl restart networks-apply")
        else:
            nets = ", ".join(f"{n} ({sum(1 for st in s.nets['stations'].values() if st.get('network') == n)} VMs)"
                             for n in s.nets["networks"])
            lines.append(f"networks: {nets}")
    for svc in CFG["services"]:
        up = is_active(svc["unit"])
        lines.append(f"{svc['name']}: {'running' if up else 'not running'}")
        if not up:
            wrong.append(service_wrong(svc))
    ul = uplink_lines()
    if ul is None:
        lines.append("uplinks: run gate status")
        wrong.append("uplinks cannot be read here: run gate status")
    else:
        lines.extend(ul)
    net = internet()
    lines.append(f"internet: {'yes' if net else 'no'}")
    if not net:
        wrong.append("internet: no: the host reaches nothing outside. Do: gate status")
    head = ["WRONG: " + wrong[0], ""] if wrong else ["Nothing is wrong.", ""]
    ex = CFG["exchange"]
    return "\n".join(head + lines + ["", "v: the VMs, n: the networks, d: the devices, l: looking-glass, "
                                         f"{ex['section-key']}: {ex['section']}, r: read again, q: quit"])


# -------------------------------------------------------- the path check

def path_check(name):
    """The path check of the station name: one line per piece in the order
    its traffic goes, each ending yes or no with the reason, the first no on
    top in gate status's form with what to do (Nothing is wrong. without
    one), then its last refused tries. All read as the user: libvirt; ip and
    bridge for the cables; systemctl for the service VMs; over vsock with
    socat the two answer points inside them (bastion.nix's firewallCheck and
    wifiCheck). wifi-check is waited for internet-wait seconds; firewall-check
    twice that, since its own request to the internet address may take
    internet-wait by itself; what an answer point printed before its wait
    ran out is kept, a fact it did not print cannot be read."""
    wait = CFG["internetTimeout"]
    fw, wifi, switch = CFG["firewallVm"], CFG["wifiVm"], CFG["switch"]
    meaning = {svc["name"]: svc["meaning"] for svc in CFG["services"]}
    unit = {svc["name"]: svc["unit"] for svc in CFG["services"]}
    # An answer point that does not answer: its VM restarted.
    restart = {vm: f"Do: sudo systemctl restart {u}" for vm, u in unit.items()}
    gate_wifi = f"Do: gate {CFG['wifiUplink']}"
    apply_again = "Do: sudo systemctl restart networks-apply.service"

    def listing(*cmd):
        """The JSON a command prints; an empty list when it fails."""
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            return json.loads(r.stdout) if r.returncode == 0 else []
        except (OSError, subprocess.SubprocessError, ValueError):
            return []

    def ask(point, seconds, send=""):
        """The lines an answer point prints within seconds."""
        cmd = [CFG["socat"], "-t", str(seconds), "-", f"VSOCK-CONNECT:{point['cid']}:{point['port']}"]
        try:
            return subprocess.run(cmd, input=send, capture_output=True, text=True,
                                  timeout=seconds).stdout.splitlines()
        except subprocess.TimeoutExpired as e:
            out = e.stdout or b""
            return (out.decode(errors="replace") if isinstance(out, bytes) else out).splitlines()
        except (OSError, subprocess.SubprocessError):
            return []

    lines = []

    def piece(subject, fact, wrong=None):
        """A piece's line: yes, or no with the WRONG line it gives."""
        lines.append((f"{subject}: {fact + ': ' if fact else ''}{'no' if wrong else 'yes'}", wrong))

    s = State()
    nets = s.nets
    net = nets["stations"][name]["network"]
    lane = nets["networks"][net]["lane"]
    links = {x.get("ifname"): x for x in listing(CFG["ip"], "-j", "link", "show")}
    vlans = {x.get("ifname"): x.get("vlans", []) for x in listing(CFG["bridge"], "-j", "vlan", "show")}
    untagged = {"PVID", "Egress Untagged"}

    # 1. the VM's cable: on the switch with its network's lane as its
    # untagged VLAN, against its station's network.
    v = s.vm(name)
    subject = f"{name}'s cable"
    move = ""
    if v is not None:
        to = network_of(v.root, nets)
        if to is not None and to != net:
            move = f", moves to {to} at its next start"
    again = f"Do: shut {name} down and start it again"
    if v is None:
        piece(subject, "not in libvirt's store",
              f"{subject}: not in libvirt's store: {name} has no VM, so it has no cable.")
    elif not v.active:
        piece(subject, "off" + move, f"{subject}: off: {name} is off, so it has no cable. "
                                     f"Do: start {name} in the VMs section")
    elif links.get(name, {}).get("master") != switch:
        fact = f"running, not on {switch}" + move
        piece(subject, fact, f"{subject}: {fact}. {again}")
    else:
        pvid = next((x.get("vlan") for x in vlans.get(name, []) if untagged <= set(x.get("flags", []))), None)
        if pvid == lane:
            piece(subject, f"running, on {switch}, on its network {net}" + move)
        else:
            on = next((n for n, x in nets["networks"].items() if x["lane"] == pvid), "no network")
            fact = f"running, on {switch}, on {on}, its network is {net}" + move
            piece(subject, fact, f"{subject}: {fact}. {again}")

    # 2. firewall-vm's cable on the switch carries the VM's network: its lane
    # untagged for the switch's own network, else its lane.
    for c in CFG["cables"]:
        if c["switch"] != switch:
            continue
        subject = f"{fw}'s cable on {switch}"
        entry = next((x for x in vlans.get(c["name"], []) if x.get("vlan") == lane), None)
        if links.get(c["name"], {}).get("master") != switch:
            fact = f"not on {switch}"
        elif entry is None or (net == switch and not untagged <= set(entry.get("flags", []))):
            fact = f"does not carry {net}"
        else:
            fact = None
        piece(subject, fact or f"carries {net}", fact and f"{subject}: {fact}. {apply_again}")

    # 3. and 6. a service VM's unit, as the status screen reads it.
    def service(vm):
        if is_active(unit[vm]):
            piece(vm, "running")
        else:
            piece(vm, "not running", f"{vm} is not running: {meaning[vm]}. Do: sudo systemctl start {unit[vm]}")

    service(fw)

    # 4. firewall-vm's leg and the VM's line (firewall-check).
    got, tried = {}, []
    for f in ask(CFG["firewallCheck"], 2 * wait, name + "\n"):
        w = f.split()
        if w and w[0] == "tried":
            tried.append(w[1:])
        elif w:
            got[w[0]] = w[1:]
    subject = f"{fw}'s leg {net}"
    rule_again = f"Do: save {name}'s internet rule again in the networks section"
    if "unknown" in got:
        fact = f"{name} is not in networks.json"
        piece(subject, fact, f"{subject}: {fact}: firewall-apply did not load it. {rule_again}")
    elif "leg" not in got or len(got.get("line", [])) < 3:
        fact = f"cannot be read: {fw} does not answer"
        piece(subject, fact, f"{subject}: {fact}. {restart[fw]}")
    else:
        loaded, rule, count = got["line"][:3]
        rule_text = {"open": "rule open", "listed": f"rule listed, {count} names",
                     "none": "rule none: refused by its rule"}.get(rule, f"rule {rule}")
        if loaded == rule:
            line_text = "none" if rule == "none" else "loaded"
        elif loaded == "none":
            line_text = "not loaded"
        else:
            line_text = f"loaded as {loaded}"
        fact = f"{got['leg'][1]}, {name}'s line: {line_text}, {rule_text}"
        ok = got["leg"][1:2] == ["up"] and loaded == rule
        piece(subject, fact, None if ok else f"{subject}: {fact}: firewall-apply did not load it. {rule_again}")

    # 5. the cables on the other switch (ip -j link).
    others = {}
    for c in CFG["cables"]:
        if c["switch"] != switch:
            others.setdefault(c["switch"], []).append(c["name"])
    for sw, names in others.items():
        subject = " and ".join(names)
        missing = [n for n in names if links.get(n, {}).get("master") != sw]
        fact = f"not on {sw}: {', '.join(missing)}" if missing else None
        piece(subject, fact or f"on {sw}", fact and f"{subject}: {fact}. {apply_again}")

    service(wifi)

    # 7. wifi-vm's Wi-Fi (wifi-check).
    card = next((x.split(None, 2) for x in ask(CFG["wifiCheck"], wait) if x.startswith("wifi ")), None)
    subject = f"{wifi}'s Wi-Fi"
    if card and card[1] == "connected":
        piece(subject, f"connected to {card[2]}" if len(card) > 2 else "connected")
    elif card:
        piece(subject, "not connected", f"{wifi}'s Wi-Fi is not connected: {meaning[wifi]}. {gate_wifi}")
    else:
        piece(subject, f"cannot be read: {wifi} does not answer",
              f"{wifi}'s Wi-Fi cannot be read: {meaning[wifi]}. {restart[wifi]}")

    # 8. internet from firewall-vm (firewall-check).
    subject = f"internet from {fw}"
    if "internet" not in got:
        fact = f"cannot be read: {fw} does not answer"
        piece(subject, fact, f"{subject}: {fact}. {restart[fw]}")
    elif got["internet"][:1] == ["yes"]:
        piece(subject, None)
    else:
        fact = f"no answer within {wait} seconds"
        piece(subject, fact, f"{subject}: {fact}. {gate_wifi}")

    # The VM's last refused tries (firewall-check).
    if "line" not in got and "unknown" not in got:
        tail = [f"{name}'s last refused tries: cannot be read: {fw} does not answer"]
    elif tried:
        tail = [f"{name}'s last refused tries:"] + [", ".join(t) for t in tried]
    else:
        tail = [f"{name}'s last refused tries: none in {fw}'s journal"]

    wrong = next((w for _, w in lines if w), None)
    head = [f"WRONG: {wrong}", ""] if wrong else ["Nothing is wrong.", ""]
    return "\n".join(head + [t for t, _ in lines] + tail)


# ------------------------------------------------------------- the screens

class Ask(Screen):
    """One question on its own screen; dismissed with the picked id, or None."""
    BINDINGS = [Binding("escape", "back", "back")]

    def __init__(self, question, options, above="", meaning=""):
        super().__init__()
        self.question, self.options, self.above, self.meaning = question, options, above, meaning

    def compose(self):
        yield Header()
        yield Static(text(self.question), markup=False, classes="question")
        if self.above:
            yield Static(text(self.above), markup=False)
        yield OptionList(*[Option(text(t), id=i, disabled=d) for i, t, d in self.options])
        if self.meaning:
            yield Static(text(self.meaning), markup=False)
        yield Footer()

    def on_option_list_option_selected(self, event):
        self.dismiss(event.option_id)

    def action_back(self):
        self.dismiss(None)


class TypeIn(Screen):
    """A typed answer, checked on the spot; a refusal stays on the screen."""
    BINDINGS = [Binding("escape", "back", "back")]

    def __init__(self, question, meaning, check):
        super().__init__()
        self.question, self.meaning, self.check = question, meaning, check

    def compose(self):
        yield Header()
        yield Static(text(self.question), markup=False, classes="question")
        yield Input()
        yield Static(text(""), markup=False, id="reason")
        yield Static(text(self.meaning), markup=False)
        yield Footer()

    def on_input_submitted(self, event):
        value = event.value.strip()
        reason = self.check(value)
        if reason:
            self.query_one("#reason", Static).update(text(f"refused: {reason}"))
        else:
            self.dismiss(value)

    def action_back(self):
        self.dismiss(None)


class Lines(Screen):
    """The listed names, one per line."""
    BINDINGS = [Binding("escape", "back", "back"), Binding("ctrl+s", "save", "save")]

    def __init__(self, question, names):
        super().__init__()
        self.question, self.names = question, names

    def compose(self):
        yield Header()
        yield Static(text(self.question), markup=False, classes="question")
        yield TextArea("\n".join(self.names))
        yield Static(text(""), markup=False, id="reason")
        yield Static(text("one name per line (its subdomains are included); ctrl+s saves"), markup=False)
        yield Footer()

    def action_save(self):
        names = [n.strip() for n in self.query_one(TextArea).text.splitlines() if n.strip()]
        bad = [n for n in names if not all(c.isascii() and (c.isalnum() or c in ".-") for c in n)]
        if bad:
            self.query_one("#reason", Static).update(text(f"refused: not a name: {', '.join(bad)}"))
            return
        self.dismiss(names)

    def action_back(self):
        self.dismiss(None)


class Tell(Screen):
    """Text to read; Enter goes on, Escape goes back."""
    BINDINGS = [Binding("enter", "go", "go on"), Binding("escape", "back", "back")]

    def __init__(self, body):
        super().__init__()
        self.body = body

    def compose(self):
        yield Header()
        yield Static(text(self.body), markup=False)
        yield Footer()

    def action_go(self):
        self.dismiss(True)

    def action_back(self):
        self.dismiss(False)


class Pick(Screen):
    """Any number of options picked on one screen; dismissed with the ids
    picked (none is an answer), or None. Space or Enter picks and unpicks
    (textual's SelectionList), ctrl+s goes on. The ids in picked start
    picked (a Selection's initial state)."""
    BINDINGS = [Binding("escape", "back", "back"), Binding("ctrl+s", "go", "go on")]

    def __init__(self, question, options, meaning="", picked=()):
        super().__init__()
        self.question, self.options, self.meaning, self.picked = question, options, meaning, picked

    def compose(self):
        yield Header()
        yield Static(text(self.question), markup=False, classes="question")
        yield SelectionList(*[Selection(text(t), i, i in self.picked) for i, t in self.options])
        if self.meaning:
            yield Static(text(self.meaning), markup=False)
        yield Footer()

    def action_go(self):
        self.dismiss(self.query_one(SelectionList).selected)

    def action_back(self):
        self.dismiss(None)


def disk_line(s):
    promised = sum(max(v.capacity - v.allocation, 0) for v in s.vms)
    return (f"{max(s.room(), 0) // GIB} GB of the disk are free for VM disks: {s.host.free // GIB} GB are free, "
            f"{CFG['share']['disk']} GB stay for the host, {promised // GIB} GB are promised to VM disks that may still grow")


def graphics_options(s, now):
    opts = [("emulated", "emulated only (a window on the host)" + (" (now)" if now == "emulated" else ""), False)]
    for i, d in enumerate(s.devices):
        if d["passthrough"]:
            held = f"; held now by {', '.join(d['holders'])}" if d["holders"] else ""
            opts.append((f"card{i}", f"emulated plus the {d['name']} (one VM at a time; shown through looking-glass{held})"
                         + (" (now)" if now == f"card{i}" else ""), False))
        else:
            opts.append((f"host{i}", device_line(d), True))
    return opts


def functions_of(s, pick):
    if pick and pick.startswith("card"):
        return s.devices[int(pick[4:])]["functions"]
    return []


def graphics_text(s, pick):
    if pick and pick.startswith("card"):
        return f"emulated plus the {s.devices[int(pick[4:])]['name']}"
    return "emulated only"


async def ask_rule(screen, now, names):
    """The internet rule, and for listed its names."""
    rule = await screen.app.push_screen_wait(Ask("Internet", [
        ("open", "open: the whole internet, logged" + (" (now)" if now == "open" else ""), False),
        ("listed", "listed: only the names you type, each on its own line" + (" (now)" if now == "listed" else ""), False),
        ("none", "none: no internet; every try is logged" + (" (now)" if now == "none" else ""), False)],
        meaning="a change of the internet rule takes effect at once"))
    if rule == "listed":
        picked = await screen.app.push_screen_wait(Lines("The names it may reach", names))
        if picked is None:
            return None, []
        return rule, picked
    return rule, []


class RuleScreen(Screen):
    """A screen that changes a VM's internet rule: the VM screen and the
    networks section; each has its own say()."""

    async def change_rule(self, v):
        nets = read_networks()
        st = nets["stations"].get(v.name)
        if st is None:
            self.say(f"{v.name} has no entry in networks.json.")
            return
        rule, names = await ask_rule(self, st["rule"], st.get("names", []))
        if rule is None:
            return
        st["rule"] = rule
        if rule == "listed":
            st["names"] = names
        else:
            st.pop("names", None)
        rc, out = write_networks(self.app, nets)
        self.say(("saved and applied: " if rc == 0 else "not applied: ") + out)


class StatusScreen(Screen):
    """The status screen; status_screen makes the class the tool shows, with
    the broker section's key, read again and quit after these keys."""
    BINDINGS = [Binding("v", "vms", "VMs"), Binding("n", "networks", "networks"),
                Binding("d", "devices", "devices"), Binding("l", "glass", "looking-glass")]

    def compose(self):
        yield Header()
        yield Static(text("reading the host ..."), markup=False, id="status")
        yield Footer()

    def on_mount(self):
        self.sub_title = "status"
        self.action_read()

    def action_read(self):
        self.query_one("#status", Static).update(text("reading the host ..."))
        self.read_status()

    @work(thread=True, exclusive=True)
    def read_status(self):
        body = status_text()
        self.app.call_from_thread(self.show, body)

    def show(self, body):
        self.query_one("#status", Static).update(text(body))

    def action_vms(self):
        self.app.push_screen(VmsScreen())

    def action_networks(self):
        self.app.push_screen(NetworksScreen())

    def action_devices(self):
        self.app.push_screen(DevicesScreen())

    def action_glass(self):
        self.app.push_screen(GlassScreen())

    def action_broker(self):
        self.app.push_screen(BrokerScreen())


def status_screen():
    """The status screen the tool shows: textual reads a screen's keys when
    its class is made (textual 8.2.6 dom.py 565-591, 671-695), and the broker
    section's key is the settings', read when main starts, so this class is
    made after that: StatusScreen's keys, then that key, read again and
    quit, in the order of the keys line."""
    ex = CFG["exchange"]
    keys = [Binding(ex["section-key"], "broker", ex["section"]),
            Binding("r", "read", "read again"), Binding("q", "app.quit", "quit")]
    return types.new_class(StatusScreen.__name__, (StatusScreen,), {},
                           lambda ns: ns.update(BINDINGS=keys, __module__=__name__))()


class DevicesScreen(Screen):
    BINDINGS = [Binding("escape", "app.pop_screen", "back"), Binding("r", "read", "read again")]

    def compose(self):
        yield Header()
        yield Static(text(""), markup=False, id="devices")
        yield Footer()

    def on_mount(self):
        self.sub_title = "devices"
        self.action_read()

    def action_read(self):
        try:
            s = State()
            body = "\n".join(device_line(d) for d in s.devices) or "no graphics device found"
        except libvirt.libvirtError as e:
            body = f"libvirt cannot be read: {e}"
        self.query_one("#devices", Static).update(text(body))


class VmsScreen(Screen):
    """The VMs section: the VMs, a new VM, and the two actions of the copy
    folder, "copy firmware and TPM" and "restore"."""
    BINDINGS = [Binding("n", "new", "new VM"), Binding("r", "read", "read again"),
                Binding("escape", "app.pop_screen", "back")]
    ACTIONS = [("copy", "copy firmware and TPM"), ("restore", "restore")]

    def compose(self):
        yield Header()
        yield DataTable(cursor_type="row", id="vms")
        yield OptionList(*[Option(text(t), id=i) for i, t in self.ACTIONS], id="actions")
        yield Static(text(""), markup=False, id="message")
        yield Footer()

    def on_option_list_option_selected(self, event):
        if event.option_list.id == "actions":
            if event.option_id == "copy":
                self.copy_state()
            else:
                self.restore()

    @work(exclusive=True)
    async def copy_state(self):
        """copy firmware and TPM: state-copy save for every VM the tool owns
        (each VM of libvirt's store that Nix does not define), the screen
        given to the terminal once for them all, so sudo can ask there; a
        running VM is named and skipped, since QEMU and swtpm write those
        files while it runs. One line per VM: copied, or the failure."""
        try:
            s = State()
        except libvirt.libvirtError as e:
            self.say(f"libvirt cannot be read: {e}")
            return
        folder = CFG["copyDir"]
        try:
            os.makedirs(folder, exist_ok=True)
        except OSError as e:
            self.say(f"nothing copied: {e}")
            return
        lines = []
        with self.app.suspend():
            print("state-copy runs (sudo may ask your password) ...", flush=True)
            for v in s.vms:
                if v.nix:
                    continue
                if v.active:
                    lines.append(f"{v.name}, runs, shut it down first")
                    continue
                uuid = v.root.findtext("uuid")
                r = subprocess.run(["sudo", CFG["privileged"]["state-copy"], "save", v.name, uuid],
                                   text=True, capture_output=True)
                out = (r.stdout + r.stderr).strip()
                where = os.path.join(folder, "state", v.name)
                if r.returncode:
                    lines.append(f"{v.name}, not copied: {out.splitlines()[-1] if out else r.returncode}")
                elif os.path.isdir(os.path.join(where, uuid)):
                    lines.append(f"{v.name}, firmware variables and TPM state copied into {where}")
                else:
                    lines.append(f"{v.name}, firmware variables copied, no TPM state")
        self.say("\n".join(lines) or "no VM to copy")

    @work(exclusive=True)
    async def restore(self):
        """restore: the VMs saved in the copy folder that libvirt does not
        hold now, a template whose sealed mark exists left out (restoring it
        would undo its seal); any number picked on one screen, then one kind
        for them all: definitions only, or whole for the picked VMs that have
        a state folder, the others then coming back with their definitions
        only. Whole: state-copy restore first, then the definition; then one
        networks-write with the restored VMs' stations from the copy
        (guards.restore_networks). A VM defined now is left as it is."""
        try:
            s = State()
        except libvirt.libvirtError as e:
            self.say(f"libvirt cannot be read: {e}")
            return
        folder = CFG["copyDir"]
        defined = {v.name for v in s.vms}
        sealed = {p["name"] for p in CFG["templates"] if os.path.exists(p["sealed"])}
        try:
            saved = sorted(e[:-len(".xml")] for e in os.listdir(folder) if e.endswith(".xml"))
        except FileNotFoundError:
            saved = []
        here = [n for n in saved if n in defined]
        offered = [n for n in saved if n not in defined and n not in sealed]
        left = f"defined now, left as they are: {', '.join(here)}" if here else ""
        if not offered:
            self.say("no saved VM to restore" + (f"\n{left}" if left else ""))
            return
        state = {n: os.path.isdir(os.path.join(folder, "state", n)) for n in offered}
        picked = await self.app.push_screen_wait(Pick(
            f"Restore: the VMs saved in {folder} that are not defined now",
            [(n, f"{n}, with saved firmware and TPM" if state[n] else f"{n}, definition only saved")
             for n in offered],
            meaning=(f"{left}\n" if left else "") + "space or Enter picks and unpicks, ctrl+s goes on"))
        if not picked:
            return
        kind = await self.app.push_screen_wait(Ask("Which kind of restore?", [
            ("definitions", "definitions only (fresh firmware and TPM)", False),
            ("whole", "whole (with the saved firmware and TPM)", not any(state[n] for n in picked))]))
        if kind is None:
            return
        lines, restored = [], []
        for name in sorted(picked):
            try:
                with open(os.path.join(folder, name + ".xml"), encoding="utf-8") as f:
                    xml = f.read()
                uuid = ET.fromstring(xml).findtext("uuid") or ""
            except (OSError, ET.ParseError) as e:
                lines.append(f"{name}, not restored: {e}")
                continue
            whole = kind == "whole" and state[name]
            if whole:
                rc, out = run_step(self.app, "state-copy", ["restore", name, uuid],
                                   note=f"state-copy puts {name}'s firmware variables and TPM state back "
                                        "(sudo may ask your password) ...")
                if rc:
                    lines.append(f"{name}, not restored: {out.splitlines()[-1] if out else rc}")
                    continue
            try:
                s.conn.defineXMLFlags(xml, libvirt.VIR_DOMAIN_DEFINE_VALIDATE)
            except libvirt.libvirtError as e:
                lines.append(f"{name}, not restored: {e}")
                continue
            CHANGED.add(name)
            restored.append(name)
            lines.append(f"{name}, restored whole" if whole else f"{name}, restored, definition only")
        if restored:
            try:
                with open(os.path.join(folder, "networks.json"), encoding="utf-8") as f:
                    copied = json.load(f)
                nets = read_networks()
            except (OSError, ValueError) as e:
                lines.append(f"no station taken from the copy: {e}")
            else:
                nets, stations, networks = guards.restore_networks(nets, copied, restored)
                if stations:
                    rc, out = write_networks(self.app, nets)
                    lines.append(f"stations added: {', '.join(stations)}")
                    if networks:
                        lines.append(f"networks added: {', '.join(networks)}")
                    lines.append(("saved and applied: " if rc == 0 else "not applied: ") + out)
        self.say("\n".join(lines))
        self.action_read()
        write_copy(self.app)

    def on_mount(self):
        self.sub_title = "VMs"

    def on_screen_resume(self):
        self.action_read()

    def say(self, body):
        self.query_one("#message", Static).update(text(body))

    def action_read(self):
        table = self.query_one(DataTable)
        table.clear(columns=True)
        table.add_columns(*[text(c) for c in ("name", "state", "cores", "RAM", "disk", "graphics",
                                              "network", "internet rule")])
        try:
            s = State()
        except libvirt.libvirtError as e:
            self.say(f"libvirt cannot be read: {e}")
            return
        for v in s.vms:
            table.add_row(*[text(c) for c in v.row(s.devices)], key=v.name)

    def on_data_table_row_selected(self, event):
        self.app.push_screen(VmScreen(event.row_key.value))

    def action_new(self):
        self.new_vm()

    async def ask(self, question, options, above="", meaning=""):
        return await self.app.push_screen_wait(Ask(question, options, above, meaning))

    @work(exclusive=True)
    async def new_vm(self):
        s = State()
        h = s.host
        used = {v.name for v in s.vms} | set(s.nets.get("stations", {})) | set(CFG["namesInUse"])
        retired = set(os.listdir(CFG["retired"])) if os.path.isdir(CFG["retired"]) else set()
        name = await self.app.push_screen_wait(TypeIn(
            "1. Name",
            f"letters, digits and dashes, at most {CFG['nameMax']} characters; the name is also the VM's cable",
            lambda n: guards.name_refusal(n, used, retired, CFG["nameMax"], CFG["refusedPrefixes"])))
        if name is None:
            return
        opts = []
        for p in CFG["templates"]:
            ready = os.path.exists(p["sealed"])
            opts.append((p["t"], p["t"] if ready else f"{p['t']}: not ready: install Windows in it first", not ready))
        t = await self.ask("2. Windows", opts, meaning="the VM is an independent copy of the sealed template")
        if t is None:
            return
        p = template_of(t)
        cores = await self.ask("3. Cores", [(str(n), f"{n} threads", False) for n in
                                            guards.core_offers(h.load(), CFG["share"], CFG["services"], h.threads_per_core)],
                               above=s.holding(),
                               meaning="only counts that fit are offered; a start is refused while the running VMs together would pass the host")
        if cores is None:
            return
        cores = int(cores)
        fast = await self.ask("3b. Fast cores first?", [
            ("yes", f"fast cores first ({h.count('fast')} fast threads on this host): for VMs that need speed, such as games", False),
            ("no", f"dense cores first ({h.count('dense')} dense threads), then fast ones", False)],
            meaning="at each start the VM is pinned to free cores of its kind first; the start screen says when it shares")
        if fast is None:
            return
        ram = await self.ask("4. RAM", [(str(g), f"{g} GB", False) for g in
                                        guards.ram_offers(h.load(), CFG["share"], CFG["services"], CFG["steps"]["ram"])],
                             above=s.holding(), meaning="RAM the VM gets while it runs")
        if ram is None:
            return
        room = s.room()
        sizes = guards.new_disk_offers(p["disk"], room, CFG["steps"]["disk"])
        if not sizes:
            await self.app.push_screen_wait(Tell(
                f"The disk has room for no new VM: {max(room, 0) // GIB} GB are free for VM disks, "
                f"the template needs {p['disk']} GB."))
            return
        disk = await self.ask("5. Disk", [(str(g), f"{g} GB", False) for g in sizes],
                              above=disk_line(s),
                              meaning="a disk can be made bigger later, never smaller")
        if disk is None:
            return
        card = await self.ask("6. Graphics", graphics_options(s, None),
                              meaning="a VM with a card shows its screen through looking-glass")
        if card is None:
            return
        network = await self.ask("7. Network", [(n, n, False) for n in s.nets.get("networks", {})],
                                 meaning="the network the VM's cable is on")
        if network is None:
            return
        rule, names = await ask_rule(self, None, [])
        if rule is None:
            return
        functions = functions_of(s, card)
        summary = (f"8. The VM {name}:\n"
                   f"  Windows: {t}\n  cores: {cores} threads, {'fast' if fast == 'yes' else 'dense'} cores first\n"
                   f"  RAM: {ram} GB\n  disk: {disk} GB\n  graphics: {graphics_text(s, card)}\n"
                   f"  network: {network}\n  internet: {rule}" + (f" ({', '.join(names)})" if rule == "listed" else "")
                   + "\n\nEnter: make it.")
        if not await self.app.push_screen_wait(Tell(summary)):
            return
        await self.make(s, name, p, cores, fast == "yes", int(ram), int(disk), functions, network, rule, names)
        write_copy(self.app)

    async def make(self, s, name, p, cores, fast, ram, disk, functions, network, rule, names):
        rc, out = run_step(self.app, "make-disk", [p["t"], name, str(disk)],
                           note=f"make-disk copies {p['t']} into {name}'s disk (a few minutes; sudo may ask your password) ...")
        if rc:
            self.say(f"{name} is not made: make-disk failed: {out}")
            return
        lg = looking_glass() if functions else None
        if functions and lg is None:
            self.say(f"{name}'s disk is made, the VM is not: looking-glass's shared memory is not on the host.")
            return
        pins, _ = guards.pins_at_start(s.host.cores, s.host.kind, cores, fast, {})
        disk_file = os.path.join(CFG["images"], name + ".qcow2")
        nets = read_networks()
        root = ET.fromstring(domain_xml(name, ram * MIB_PER_GIB, cores, pins, s.host, disk_file,
                                        p["win11"], functions, lg))
        set_lane(root, nets, network)
        try:
            dom = s.conn.defineXMLFlags(xml_text(root), libvirt.VIR_DOMAIN_DEFINE_VALIDATE)
        except libvirt.libvirtError as e:
            self.say(f"{name}'s disk is made, the VM is not defined: {e}")
            return
        CHANGED.add(name)
        mac =ET.fromstring(dom.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)).find("./devices/interface/mac").get("address")
        ip = free_address(nets, network)
        entry = {"network": network, "ip": ip, "mac": mac, "rule": rule}
        if rule == "listed":
            entry["names"] = names
        nets["stations"][name] = entry
        rc, out = write_networks(self.app, nets)
        self.action_read()
        if rc:
            self.say(f"{name} is defined; its address and rule were not applied: {out}")
            return
        await self.app.push_screen_wait(Tell(
            f"{name} is made: address {ip}, internet {rule}.\n{out}\n\n"
            f"Its first start: open it and pick 'first start'; that start runs without network."))


class VmScreen(RuleScreen):
    """One VM: its settings, each changed on its own screen, and its actions."""
    BINDINGS = [Binding("escape", "app.pop_screen", "back")]
    ACTIONS = [("start", "start"), ("first", "first start (no network for that start)"),
               ("shutdown", "shut down"), ("window", "open its window"), ("console", "console"), ("cores", "cores"),
               ("fast", "fast cores first"), ("ram", "RAM"), ("disk", "disk"), ("graphics", "graphics"),
               ("internet", "internet rule"), ("retire", "retire")]

    def __init__(self, name):
        super().__init__()
        self.vm_name = name

    def compose(self):
        yield Header()
        yield Static(text(""), markup=False, id="details")
        yield OptionList(*[Option(text(t), id=i) for i, t in self.ACTIONS], id="actions")
        yield Static(text(""), markup=False, id="message")
        yield Footer()

    def on_mount(self):
        self.sub_title = self.vm_name

    def on_screen_resume(self):
        self.read()

    def say(self, body):
        self.query_one("#message", Static).update(text(body))

    def read(self):
        self.state = State()
        v = self.state.vm(self.vm_name)
        if v is None:
            self.query_one("#details", Static).update(text(f"{self.vm_name} is not in libvirt's store."))
            return None
        h = self.state.host
        kinds = guards.kinds_of(v.live_pins, h.kind) if v.active else (
            f"{'fast' if v.fast_first(h) else 'dense'} cores first")
        lines = [f"{v.name}: {'running' if v.active else 'off'}",
                 f"cores: {v.vcpus} threads; {kinds}",
                 f"RAM: {gb(v.memory)} GB", f"disk: {v.capacity // GIB} GB",
                 f"graphics: {v.graphics(self.state.devices)}",
                 f"network: {v.station['network'] if v.station else '-'}; internet rule: {v.rule()}"
                 + (f"; address {v.station['ip']}" if v.station else "")]
        if v.nix:
            lines.append("defined by Nix, which rewrites it at every boot")
        self.query_one("#details", Static).update(text("\n".join(lines)))
        return v

    def on_option_list_option_selected(self, event):
        if event.option_list.id == "actions":
            self.act(event.option_id)

    async def ask(self, question, options, above="", meaning=""):
        return await self.app.push_screen_wait(Ask(question, options, above, meaning))

    def saved(self, v, what):
        self.say(f"saved: {what}" + ("; takes effect at its next start" if v.active else ""))

    @work(exclusive=True)
    async def act(self, what):
        v = self.read()
        if v is None:
            return
        s, h = self.state, self.state.host
        try:
            if what in ("start", "first"):
                await self.start(s, v, what == "first")
            elif what == "shutdown":
                s.conn.lookupByName(v.name).shutdown()
                self.say(f"{v.name} is shutting down: Windows ends by itself.")
            elif what == "window":
                open_window(v)
                self.say(f"{v.name}'s window opens.")
            elif what == "console":
                open_console(v.name)
                self.say(f"{v.name}'s console opens.")
            elif what == "cores":
                n = await self.ask("Cores", [(str(c), f"{c} threads" + (" (now)" if c == v.vcpus else ""), False)
                                             for c in guards.core_offers(h.load(), CFG["share"], CFG["services"],
                                                                         h.threads_per_core)],
                                   above=s.holding(), meaning="takes effect at the VM's next start")
                if n is not None:
                    n = int(n)
                    pins, _ = guards.pins_at_start(h.cores, h.kind, n, v.fast_first(h), {})
                    back = redefine(s.conn, v.name, lambda r: set_cpu(r, n, pins, h))
                    self.saved(v, f"{back.findtext('vcpu')} threads")
            elif what == "fast":
                now = "yes" if v.fast_first(h) else "no"
                f = await self.ask("Fast cores first?", [
                    ("yes", "fast cores first: for VMs that need speed, such as games" + (" (now)" if now == "yes" else ""), False),
                    ("no", "dense cores first, then fast ones" + (" (now)" if now == "no" else ""), False)],
                    meaning="at each start the VM is pinned to free cores of its kind first")
                if f is not None:
                    pins, _ = guards.pins_at_start(h.cores, h.kind, v.vcpus, f == "yes", {})
                    back = redefine(s.conn, v.name, lambda r: set_pins(r, pins, h))
                    got = "fast" if guards.fast_first_of(first_pins(back), h.kind) else "dense"
                    self.saved(v, f"{got} cores first")
            elif what == "ram":
                g = await self.ask("RAM", [(str(x), f"{x} GB" + (" (now)" if x * MIB_PER_GIB == v.memory else ""), False)
                                           for x in guards.ram_offers(h.load(), CFG["share"], CFG["services"],
                                                                      CFG["steps"]["ram"])],
                                   above=s.holding(), meaning="takes effect at the VM's next start")
                if g is not None:
                    back = redefine(s.conn, v.name, lambda r: set_memory(r, int(g) * MIB_PER_GIB))
                    self.saved(v, f"{gb(memory_mib(back.find('memory')))} GB of RAM")
            elif what == "disk":
                await self.grow(s, v)
            elif what == "graphics":
                now = "emulated"
                for i, d in enumerate(s.devices):
                    if set(v.hostdevs) & set(d["functions"]):
                        now = f"card{i}"
                pick = await self.ask("Graphics", graphics_options(s, now),
                                      meaning="takes effect at the VM's next start")
                if pick is not None:
                    functions = functions_of(s, pick)
                    lg = looking_glass() if functions else None
                    if functions and lg is None:
                        self.say("not saved: looking-glass's shared memory is not on the host.")
                        return
                    redefine(s.conn, v.name, lambda r: set_card(r, functions, lg))
                    self.saved(v, graphics_text(s, pick))
            elif what == "internet":
                await self.change_rule(v)
            elif what == "retire":
                await self.retire(s, v)
        except libvirt.libvirtError as e:
            self.say(f"not done: {e}")
        if what != "retire":
            self.read()
        write_copy(self.app)

    async def start(self, s, v, first):
        if v.active:
            self.say(f"{v.name} runs already.")
            return
        h = s.host
        refusals, pins, lines, vsock = start_plan(s, v, first)
        if refusals:
            await self.app.push_screen_wait(Tell(f"{v.name} cannot start now:\n" + "\n".join(refusals)))
            return
        warning = firewall_warning()
        if not await self.app.push_screen_wait(Tell("\n".join(lines + ([warning] if warning else []))
                                                    + "\n\nEnter: start it.")):
            return
        # The line is on the screen before the start, which holds the event
        # loop until it ends: wait_for_refresh returns once the screen is
        # refreshed (textual 8.2.6 message_pump.py 469-488, screen.py 1236-1262).
        self.say(f"starting {v.name} ...")
        await self.wait_for_refresh()
        moved = station_follows(self.app, v)
        try:
            start_vm(s.conn, h, v.name, pins, vsock, first)
        except libvirt.libvirtError as e:
            self.say(f"not started: {e}")
            return
        if first:
            FIRST_STARTED.add(v.name)
        # Its window and the wait: the command line's bastion start or bastion
        # first, a process of its own in a session of its own, which finds
        # the VM running, so it opens the window and holds sleep off until
        # the VM is off, whether these screens stay open or not.
        subprocess.Popen([sys.executable, os.path.abspath(__file__), sys.argv[1], "first" if first else "start",
                          v.name], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        said = f"{v.name} runs on {guards.kinds_of(pins, h.kind)}. {LID_WARNING}"
        if moved:
            said += ("\nsaved and applied: " if moved[0] == 0 else "\nnot applied: ") + moved[1]
        self.say(said)

    async def grow(self, s, v):
        room = s.room()
        current = v.capacity // GIB
        sizes = guards.grow_offers(current, room, CFG["steps"]["disk"])
        if not sizes:
            self.say(f"{v.name}'s disk cannot grow: {max(room, 0) // GIB} GB are free for VM disks.")
            return
        g = await self.ask("Disk", [(str(x), f"{x} GB", False) for x in sizes],
                           above=f"now {current} GB; " + disk_line(s),
                           meaning="bigger only: a disk is never made smaller; C: is extended inside Windows "
                                   "by the presets script 70-grow-c")
        if g is None:
            return
        g = int(g)
        dom = s.conn.lookupByName(v.name)
        if v.active:
            dom.blockResize(v.disk_target, g * GIB, libvirt.VIR_DOMAIN_BLOCK_RESIZE_BYTES)
            self.say(f"{v.name}'s disk is {dom.blockInfo(v.disk_target)[0] // GIB} GB now; "
                     "extend C: inside Windows (70-grow-c).")
        else:
            rc, out = run_step(self.app, "disk-grow", [v.name, str(g)])
            self.say(out if rc == 0 else f"not grown: {out}")

    async def retire(self, s, v):
        if v.active:
            self.say(f"{v.name} runs: shut it down first.")
            return
        where = os.path.join(CFG["retired"], v.name)
        ip = v.station["ip"] if v.station else "-"
        if not await self.app.push_screen_wait(Tell(
                f"Retire {v.name}?\nIt leaves the list. Its disk, its definition, its firmware variables and "
                f"its TPM state are moved into {where}; nothing is deleted. Its address {ip} becomes free "
                "for a new VM.\n\nEnter: retire it.")):
            return
        rc, out = run_step(self.app, "disk-retire", [v.name])
        if rc:
            self.say(f"not retired: {out}")
            return
        s.conn.lookupByName(v.name).undefineFlags(
            libvirt.VIR_DOMAIN_UNDEFINE_KEEP_NVRAM | libvirt.VIR_DOMAIN_UNDEFINE_KEEP_TPM)
        CHANGED.add(v.name)
        nets = read_networks()
        if v.name in nets["stations"]:
            del nets["stations"][v.name]
            rc, out2 = write_networks(self.app, nets)
            if rc:
                out = f"its address was not freed: {out2}"
        self.app.pop_screen()
        self.app.notify(f"{v.name} is retired into {where}. {out}")


def station_line(s, name):
    """A station's line in the networks section: its state, internet rule and
    address, and the network its definition puts it on at its next start
    when that is another one."""
    st = s.nets["stations"][name]
    v = s.vm(name)
    if v is None:
        return f"{name}: not in libvirt's store, internet {st['rule']}, address {st['ip']}"
    line = f"{name}: {'running' if v.active else 'off'}, internet {v.rule()}, address {st['ip']}"
    to = network_of(v.root, s.nets)
    if to is not None and to != st["network"]:
        line += f", moves to {to} at its next start"
    return line


class NetworksScreen(RuleScreen):
    """The networks of networks.json, each with its VMs; a network picked
    switches whether its VMs reach each other; a VM picked changes its
    internet rule, moves to a network or shows its path check; and a new
    network, made while the system runs."""
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]
    ACTIONS = [("new", "new network")]
    # A network's entry in the list: its id, which no VM's name can be
    # (a name holds no space).
    NETWORK = "network "

    def compose(self):
        yield Header()
        yield OptionList(id="networks")
        yield OptionList(*[Option(text(t), id=i) for i, t in self.ACTIONS], id="actions")
        yield Static(text(""), markup=False, id="message")
        yield Static(text("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = "networks"

    def on_screen_resume(self):
        self.action_read()

    def say(self, body):
        self.query_one("#message", Static).update(text(body))

    def action_read(self):
        listing = self.query_one("#networks", OptionList)
        listing.clear_options()
        try:
            s = State()
        except libvirt.libvirtError as e:
            self.say(f"libvirt cannot be read: {e}")
            return
        if s.nets_error:
            self.say(f"networks.json cannot be read ({s.nets_error}).")
            return
        for n, net in s.nets["networks"].items():
            names = sorted(k for k, st in s.nets["stations"].items() if st.get("network") == n)
            listing.add_option(Option(text(f"{n}: {net['ip-range']}, {len(names)} VMs\n"
                                           f"VMs reach each other: {'yes' if net['reach-each-other'] else 'no'}"),
                                      id=self.NETWORK + n))
            listing.add_options([Option(text(station_line(s, k)), id=k) for k in names])

    def on_option_list_option_selected(self, event):
        if event.option_list.id == "actions":
            self.new_network()
        elif event.option_id.startswith(self.NETWORK):
            self.switch(event.option_id.removeprefix(self.NETWORK))
        else:
            self.pick(event.option_id)

    @work(exclusive=True)
    async def switch(self, name):
        """The network's reach-each-other: networks-write first, then the
        definition of every VM it puts on the network, from the value read
        back."""
        nets = read_networks()
        now = nets["networks"][name]["reach-each-other"]
        picked = await self.app.push_screen_wait(Ask(f"{name}: VMs reach each other", [
            ("yes", "yes" + (" (now)" if now else ""), False),
            ("no", "no" + (" (now)" if not now else ""), False)],
            meaning=f"yes: the VMs on {name} reach each other directly, as on a switch of their own. "
                    f"no: each VM on {name} reaches only {CFG['firewallVm']}. Takes effect at once."))
        if picked is None:
            return
        nets["networks"][name]["reach-each-other"] = picked == "yes"
        rc, out = write_networks(self.app, nets)
        said = ("saved and applied: " if rc == 0 else "not applied: ") + out
        try:
            s = State()
        except libvirt.libvirtError as e:
            self.say(said + f"\nnot done: {e}")
            return
        for v in s.vms:
            if network_of(v.root, s.nets) == name:
                try:
                    redefine(s.conn, v.name, lambda r: set_lane(r, s.nets, name))
                except libvirt.libvirtError as e:
                    said += f"\nnot done: {v.name}: {e}"
        self.say(said)
        self.action_read()
        write_copy(self.app)

    @work(exclusive=True)
    async def pick(self, name):
        s = State()
        v = s.vm(name)
        opts = [("internet", "internet rule", False)]
        if v is not None and not v.nix:
            opts.append(("move", "move to a network", False))
        opts.append(("path", "path check", False))
        what = await self.app.push_screen_wait(Ask(name, opts, above=station_line(s, name)))
        try:
            if what == "internet":
                await self.change_rule(v if v is not None else types.SimpleNamespace(name=name))
            elif what == "move":
                await self.move(s, v)
            elif what == "path":
                self.app.push_screen(PathScreen(name))
        except libvirt.libvirtError as e:
            self.say(f"not done: {e}")
        self.action_read()
        write_copy(self.app)

    async def move(self, s, v):
        """An off VM moves at once: its definition, and its station with an
        address of the new network. A running VM's definition alone changes;
        its station follows at its next start (station_follows)."""
        st = s.nets["stations"][v.name]
        there = network_of(v.root, s.nets)
        to = await self.app.push_screen_wait(Ask(f"Move {v.name} to a network", [
            (n, f"{n}: {net['ip-range']}" + (" (now)" if n == st["network"] else ""),
             n == st["network"] and n == there)
            for n, net in s.nets["networks"].items()],
            meaning="an off VM moves at once and gets an address of that network; "
                    "a running VM moves at its next start"))
        if to is None:
            return
        redefine(s.conn, v.name, lambda r: set_lane(r, s.nets, to))
        if v.active:
            self.say("saved: takes effect at its next start")
            return
        nets = read_networks()
        st = nets["stations"][v.name]
        if st["network"] == to:
            self.say(f"saved: {v.name} is on {to}")
            return
        st["network"] = to
        st["ip"] = free_address(nets, to)
        rc, out = write_networks(self.app, nets)
        self.say(("saved and applied: " if rc == 0 else "not applied: ") + out)

    @work(exclusive=True)
    async def new_network(self):
        s = State()
        if s.nets_error:
            self.say(f"networks.json cannot be read ({s.nets_error}).")
            return
        nets = s.nets
        fw = CFG["firewallVm"]
        name = await self.app.push_screen_wait(TypeIn(
            "1. Name",
            f"letters, digits and dashes, at most {CFG['nameMax']} characters; "
            f"the name is also {fw}'s leg on this network",
            lambda n: guards.network_refusal(n, nets["networks"], CFG["hostNetworkNames"], CFG["nameMax"], fw)))
        if name is None:
            return
        vms = [v for v in s.vms if v.station is not None and not v.nix]
        picked = await self.app.push_screen_wait(Pick("2. VMs", [
            (v.name, f"{v.name}, on {v.station['network']}" + (", running: moves at its next start" if v.active else ""))
            for v in vms],
            meaning=f"the picked VMs move onto {name}; with none picked the network is made with no VM on it; "
                    "space or Enter picks and unpicks, ctrl+s goes on"))
        if picked is None:
            return
        moving = [v for v in vms if v.name in picked]
        ip_range = guards.next_range(nets["networks"], CFG["switch"])
        now = ", ".join(v.name for v in moving if not v.active)
        later = ", ".join(v.name for v in moving if v.active)
        summary = (f"3. The network {name}:\n"
                   f"range {ip_range}, {fw}'s address on it {guards.first_address(ip_range)}\n"
                   + (f"moving onto it now: {now}\n" if now else "")
                   + (f"moving onto it at their next start: {later}\n" if later else "")
                   + "\nEnter: make it.")
        if not await self.app.push_screen_wait(Tell(summary)):
            return
        try:
            await self.make(s, name, ip_range, moving)
        except libvirt.libvirtError as e:
            self.say(f"not done: {e}")
        self.action_read()
        write_copy(self.app)

    async def make(self, s, name, ip_range, moving):
        """The network written into networks.json with the VMs moving onto
        it: each one's definition first, then the one networks-write."""
        nets = read_networks()
        nets["networks"][name] = {"lane": guards.next_lane(nets["networks"]), "ip-range": ip_range,
                                  "reach-each-other": False}
        for v in moving:
            redefine(s.conn, v.name, lambda r: set_lane(r, nets, name))
            if not v.active:
                st = nets["stations"][v.name]
                st["network"] = name
                st["ip"] = free_address(nets, name)
        rc, out = write_networks(self.app, nets)
        self.say(("saved and applied: " if rc == 0 else "not applied: ") + out)


class PathScreen(Screen):
    """One VM's path check (path_check), read when the screen opens and again
    with r; while an answer point does not answer, a reading waits up to
    three times internet-wait."""
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]

    def __init__(self, name):
        super().__init__()
        self.vm_name = name

    def compose(self):
        yield Header()
        yield Static(text(""), markup=False, id="path")
        yield Static(text("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = f"path check: {self.vm_name}"
        self.action_read()

    def action_read(self):
        self.query_one("#path", Static).update(text(f"reading the path of {self.vm_name} ..."))
        self.read_path()

    @work(thread=True, exclusive=True)
    def read_path(self):
        try:
            body = path_check(self.vm_name)
        except libvirt.libvirtError as e:
            body = f"libvirt cannot be read: {e}"
        self.app.call_from_thread(self.query_one("#path", Static).update, text(body))


def broker_vms(s):
    """The VMs of the broker section: every VM the tool owns (each VM of
    libvirt's store that Nix does not define), templates left out, by
    name."""
    return [v for v in s.vms if not v.nix and not v.template]


def broker_name(s, name):
    """A name of a list of destinations as the broker section shows it: the
    host's station name as it is, a name with no VM defined now with the
    settings' mark after it."""
    if name == CFG["hostPort"] or s.vm(name) is not None:
        return name
    return f"{name} ({CFG['exchange']['retired']})"


def broker_line(s, v):
    """A VM's line in the broker section: its state and its list of
    destinations, the settings' word for an empty list or no station."""
    ex = CFG["exchange"]
    names = (v.station or {}).get(ex["sends-to"], [])
    listed = ", ".join(broker_name(s, n) for n in names) or ex["none"]
    return f"{v.name}: {'running' if v.active else 'off'}, {ex['sends-to-label']}: {listed}"


def broker_vm_line():
    """broker-vm's line: running, as the status screen shows a service VM,
    or its WRONG line with its meaning; and whether it runs."""
    svc = next(x for x in CFG["services"] if x["name"] == CFG["brokerVm"])
    up = is_active(svc["unit"])
    return (f"{svc['name']}: running" if up else "WRONG: " + service_wrong(svc)), up


def step_said(out, err):
    """What the exchange step printed, its output's lines, then its error."""
    return "\n".join(out + ([err] if err else []))


class BrokerScreen(Screen):
    """The broker section: broker-vm's line with its kept copies, then each
    VM the tool owns with the VMs it may send files to, its station's list
    in networks.json, then the section's two actions, send a file and
    transfers. A VM picked changes its list (written by networks-write with
    no rebuild), sends a file when it runs, shows its transfers or cleans
    its kept copies. The host has no line: it only receives. The figures of
    the kept copies are read through the exchange step when the section
    opens and at r."""
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]

    def compose(self):
        ex = CFG["exchange"]
        yield Header()
        yield Static(text(""), markup=False, id="broker")
        yield OptionList(id="vms")
        yield OptionList(Option(text(ex["send-action"]), id=ex["send"]),
                         Option(text(ex["transfers"]), id=ex["transfers"]), id="actions")
        yield Static(text(""), markup=False, id="message")
        yield Static(text("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = CFG["exchange"]["section"]
        self.first_read = False

    def on_screen_resume(self):
        self.list_vms()
        if not self.first_read:
            self.first_read = True
            self.call_after_refresh(self.read_first)

    def say(self, body):
        self.query_one("#message", Static).update(text(body))

    def action_read(self):
        self.read_first()
        self.list_vms()

    def read_first(self):
        """The first line: while broker-vm runs, the settings' line usage
        with the figures of the exchange step's usage, in GB with one
        decimal; else broker-vm's WRONG line. When the figures cannot be
        read, broker-vm's line, and what the step said below."""
        line, up = broker_vm_line()
        if up:
            ex = CFG["exchange"]
            rc, out, err = exchange_step(self.app, [ex["verbs"]["usage"]])
            figures = next((f for f in (o.split(", ") for o in out)
                            if len(f) == 3 and all(x.isdigit() for x in f)), None)
            if rc == 0 and figures:
                used, size, limit = (int(x) for x in figures)
                line = fill(ex["lines"]["usage"], broker=CFG["brokerVm"], used=gb_bytes(used),
                            size=gb_bytes(size), limit=gb_bytes(limit))
                if err:
                    self.say(err)
            else:
                self.say(step_said(out, err))
        self.query_one("#broker", Static).update(text(line))

    def list_vms(self):
        listing = self.query_one("#vms", OptionList)
        listing.clear_options()
        try:
            s = State()
        except libvirt.libvirtError as e:
            self.say(f"libvirt cannot be read: {e}")
            return
        if s.nets_error:
            self.say(f"networks.json cannot be read ({s.nets_error}).")
            return
        listing.add_options([Option(text(broker_line(s, v)), id=v.name) for v in broker_vms(s)])

    def on_option_list_option_selected(self, event):
        ex = CFG["exchange"]
        if event.option_list.id != "actions":
            self.pick(event.option_id)
        elif event.option_id == ex["send"]:
            self.send_any()
        else:
            self.transfers_of(None)

    @work(exclusive=True)
    async def pick(self, name):
        """A VM's line picked: its list of destinations, a file sent when it
        runs, its transfers, its kept copies cleaned."""
        s = State()
        v = s.vm(name)
        ex = CFG["exchange"]
        opts = [(ex["sends-to"], ex["sends-to-label"], False)]
        if v.active:
            opts.append((ex["send"], ex["send-action"], False))
        opts += [(ex["transfers"], ex["transfers"], False), (ex["clean"], ex["clean-action"], False)]
        what = await self.app.push_screen_wait(Ask(name, opts, above=broker_line(s, v)))
        if what == ex["sends-to"]:
            await self.sends_to(s, v)
        elif what == ex["send"]:
            await self.send_from(s, v)
        elif what == ex["transfers"]:
            await self.show_transfers(name)
        elif what == ex["clean"]:
            await self.clean(name)
        self.list_vms()
        write_copy(self.app)

    @work(exclusive=True)
    async def send_any(self):
        """The section's send a file: a running VM picked, then as a VM's
        send a file."""
        s = State()
        ex = CFG["exchange"]
        name = await self.app.push_screen_wait(Ask(ex["send-action"], [
            (v.name, broker_line(s, v), False) for v in broker_vms(s) if v.active]))
        if name is not None:
            await self.send_from(s, s.vm(name))
        self.list_vms()

    @work(exclusive=True)
    async def transfers_of(self, name):
        await self.show_transfers(name)

    async def send_from(self, s, v):
        """A file of v's Outbox, read live through the exchange step, picked;
        then a destination: the names of its list that run, or the host's
        name; Enter sends through the exchange step, its lines shown."""
        ex = CFG["exchange"]
        rc, files, err = exchange_step(self.app, [ex["outbox-folder"], v.name])
        if rc:
            self.say(step_said(files, err))
            return
        title = f"{v.name}: {ex['send-action']}"
        file = await self.app.push_screen_wait(Ask(title, [(f, f, False) for f in files]))
        if file is None:
            return
        host = CFG["hostPort"]
        running = {x.name for x in s.running()}
        dests = [n for n in (v.station or {}).get(ex["sends-to"], []) if n == host or n in running]
        to = await self.app.push_screen_wait(Ask(f"{title}: {file}", [(n, n, False) for n in dests]))
        if to is None:
            return
        rc, out, err = exchange_step(self.app, [ex["send"], v.name, file, to])
        self.say(step_said(out, err))

    async def show_transfers(self, name):
        """broker-vm's last lines of transfers, all or those naming name,
        through the exchange step."""
        ex = CFG["exchange"]
        rc, out, err = exchange_step(self.app, [ex["transfers"], str(CFG["transfersLines"])]
                                     + ([name] if name else []))
        await self.app.push_screen_wait(Tell(step_said(out, err)))

    async def clean(self, name):
        """name's kept copies cleaned through the exchange step after Enter,
        and the files of its stopped sends on the host; its lines shown, the
        count and the bytes."""
        ex = CFG["exchange"]
        picked = await self.app.push_screen_wait(Ask(f"{name}: {ex['clean-action']}",
                                                     [(ex["clean"], ex["clean-action"], False)]))
        if picked is None:
            return
        rc, out, err = exchange_step(self.app, [ex["clean"], name])
        self.say(step_said(out, err))

    async def sends_to(self, s, v):
        """The VM's list of destinations: one pick of every other VM the tool
        owns, the host's station name, and each listed name with no VM
        defined now, marked, the listed ones picked; ctrl+s writes the picked
        names, in the pick's order, as its station's list through
        networks-write, and an empty pick removes the key."""
        ex = CFG["exchange"]
        key, host = ex["sends-to"], CFG["hostPort"]
        nets = read_networks()
        st = nets["stations"].get(v.name)
        now = st.get(key, []) if st is not None else []
        offered = ([x.name for x in broker_vms(s) if x.name != v.name] + [host]
                   + [n for n in now if n != host and s.vm(n) is None])
        picked = await self.app.push_screen_wait(Pick(
            f"{v.name}: {ex['sends-to-label']}", [(n, broker_name(s, n)) for n in offered],
            meaning="space or Enter picks and unpicks, ctrl+s saves", picked=now))
        if picked is None:
            return
        if st is None:
            self.say(f"{v.name} has no entry in networks.json.")
            return
        names = [n for n in offered if n in picked]
        if names:
            st[key] = names
        else:
            st.pop(key, None)
        rc, out = write_networks(self.app, nets)
        self.say(("saved and applied: " if rc == 0 else "not applied: ") + out)


class GlassScreen(Screen):
    """The looking-glass section: glass on or off and the resolution, locked
    or following the window, for each VM whose definition holds the card,
    the window's settings in the client's per-user file, and two lines shown
    read-only."""
    BINDINGS = [Binding("r", "read", "read again"), Binding("escape", "app.pop_screen", "back")]

    def compose(self):
        yield Header()
        yield OptionList(id="glass")
        yield Static(text(""), markup=False, id="fixed")
        yield Static(text(""), markup=False, id="message")
        yield Static(text("r: read again, escape: back"), markup=False)
        yield Footer()

    def on_mount(self):
        self.sub_title = "looking-glass"

    def on_screen_resume(self):
        self.action_read()

    def say(self, body):
        self.query_one("#message", Static).update(text(body))

    def action_read(self):
        listing = self.query_one("#glass", OptionList)
        listing.clear_options()
        lg = looking_glass()
        self.query_one("#fixed", Static).update(text(
            (f"shared screen memory: {lg[1] // UNIT_BYTES['MiB']} MiB, set in the host's setup: "
             "a change is a rebuild, then a restart of the host" if lg
             else "shared screen memory: not on the host")
            + "\nclipboard: closed both ways"))
        try:
            s = State()
        except libvirt.libvirtError as e:
            self.say(f"libvirt cannot be read: {e}")
            return
        for v in s.vms:
            if any(set(v.hostdevs) & set(d["functions"]) for d in s.devices):
                st = v.station or {}
                listing.add_option(Option(text(
                    f"{v.name}, glass: {'on' if v.glass else 'off'}, resolution: "
                    + (f"locked at {st['resolution']}" if "resolution" in st else "follows the window")
                    + (", defined by Nix, which rewrites it at every boot" if v.nix else "")), id=v.name))
        listing.add_options([Option(text(f"{label}: {value}"), id=label)
                             for label, value in glass_settings().items()])

    def on_option_list_option_selected(self, event):
        if event.option_id in GLASS_OPTIONS:
            self.setting(event.option_id)
        else:
            self.pick(event.option_id)

    @work(exclusive=True)
    async def pick(self, name):
        """A VM's line picked: its glass or its resolution."""
        s = State()
        v = s.vm(name)
        what = await self.app.push_screen_wait(Ask(name, [
            ("glass", "glass", False), ("resolution", "resolution", False)]))
        if what == "glass":
            await self.vm_glass(s, v)
        elif what == "resolution":
            await self.vm_resolution(s, v)
        write_copy(self.app)

    async def vm_resolution(self, s, v):
        """The screen size the VM's Windows is locked at, or following the
        window, kept in its station in networks.json as the key resolution,
        WIDTHxHEIGHT, absent for following, and written by networks-write. The
        sizes offered: the driver's list (IDD_MODES), each that fits the
        shared memory read from the host (guards.idd_fits)."""
        if s.nets_error:
            self.say(f"networks.json cannot be read ({s.nets_error}).")
            return
        nets = s.nets
        st = nets["stations"].get(v.name)
        if st is None:
            self.say(f"{v.name} has no entry in networks.json.")
            return
        now = st.get("resolution")
        lg = looking_glass()
        sizes = [f"{w}x{h}" for w, h in IDD_MODES if lg and guards.idd_fits(w, h, lg[1], IDD_FRAMES_START)]
        picked = await self.app.push_screen_wait(Ask(f"{v.name}: resolution", [
            ("follows", "follows the window" + (" (now)" if now is None else ""), False)]
            + [(m, m + (" (now)" if m == now else ""), False) for m in sizes],
            meaning="locked: Windows keeps this size whatever the glass window does; it takes effect after "
                    "the VM's next presets run and restart of Windows. follows the window: Windows takes "
                    "the window's size, as today."))
        if picked is None:
            return
        if picked == "follows":
            st.pop("resolution", None)
        else:
            st["resolution"] = picked
        rc, out = write_networks(self.app, nets)
        self.say(("saved and applied: " if rc == 0 else "not applied: ") + out)
        self.action_read()

    async def vm_glass(self, s, v):
        """Glass on or off for one VM, written into its definition."""
        name = v.name
        picked = await self.app.push_screen_wait(Ask(f"{name}: glass", [
            ("on", "on" + (" (now)" if v.glass else ""), False),
            ("off", "off" + (" (now)" if not v.glass else ""), False)],
            meaning="on: the VM's screen opens in a window on the host through looking-glass. "
                    "off: no looking-glass window; the console opens instead. "
                    "Takes effect at the VM's next start."))
        if picked is None:
            return
        lg = looking_glass() if picked == "on" else None
        if picked == "on" and lg is None:
            self.say("not saved: looking-glass's shared memory is not on the host.")
            return
        try:
            redefine(s.conn, name, lambda r: set_glass(r, lg))
            after = State().vm(name)
        except libvirt.libvirtError as e:
            self.say(f"not done: {e}")
            return
        # The VM screen's own message.
        VmScreen.saved(self, after, f"glass {'on' if after.glass else 'off'}")
        self.action_read()

    @work(exclusive=True)
    async def setting(self, label):
        """One of the window's settings, written into the per-user file."""
        section, option, _, offered = GLASS_OPTIONS[label]
        now = glass_settings()[label]
        picked = await self.app.push_screen_wait(Ask(label.capitalize(), [
            (o, o + (" (now)" if o == now else ""), False) for o in offered],
            meaning="takes effect at the next window opened"))
        if picked is None:
            return
        try:
            write_glass_option(section, option, picked)
        except OSError as e:
            self.say(f"not saved: {e}")
            return
        self.say(f"saved: {label} {glass_settings()[label]}")
        self.action_read()


class Bastion(App):
    CSS = """
    .question { text-style: bold; margin: 1 0; }
    DataTable { height: 1fr; }
    OptionList { height: auto; max-height: 60%; }
    TextArea { height: 12; }
    """

    def on_mount(self):
        # The screens' title: the command's name from the settings.
        self.title = CFG["command"]
        self.push_screen(status_screen())


# ------------------------------------------------------ the command line

def define_template(p, made):
    """tpl-T defined as bastion template defines it, make-disk T first unless
    make-disk ran already in this bastion template."""
    if not made:
        rc, _ = run_step(None, "make-disk", [p["t"]])
        if rc:
            print(f"{CFG['command']}: make-disk failed (lines above).")
            return 1
    conn = connect()
    host = Host(conn)
    nets = read_networks()
    st = nets["stations"][p["name"]]
    pins, _ = guards.pins_at_start(host.cores, host.kind, p["vcpus"], False, {})
    root = ET.fromstring(domain_xml(p["name"], p["memory"], p["vcpus"], pins, host, p["file"], p["win11"],
                                    uuid=p["uuid"], mac=st["mac"], iso=p["iso"]))
    set_lane(root, nets, CFG["switch"])
    conn.defineXMLFlags(xml_text(root), libvirt.VIR_DOMAIN_DEFINE_VALIDATE)
    CHANGED.add(p["name"])
    print(f"{p['name']} is defined.")
    return 0


def seal_template(conn, p):
    conn.lookupByName(p["name"]).undefineFlags(
        libvirt.VIR_DOMAIN_UNDEFINE_KEEP_NVRAM | libvirt.VIR_DOMAIN_UNDEFINE_KEEP_TPM)
    CHANGED.add(p["name"])
    print(f"{p['name']} is no longer defined; its disk, firmware variables and TPM state stay.")


def list_step():
    """bastion list: every VM that is not a template, its state in virsh's
    words, its disk's size in GiB and the card it holds by libvirt's name for
    the device; then each template, sealed, its state, or no image yet."""
    s = State()
    for v in s.vms:
        if v.template:
            continue
        cards = [d["name"] for d in s.devices if set(v.hostdevs) & set(d["functions"])]
        print(", ".join([v.name, vm_state(s.conn, v.name) or "not made", f"{v.capacity // GIB} GiB"] + cards))
    for p in CFG["templates"]:
        if os.path.exists(p["sealed"]):
            st = "sealed"
        else:
            st = vm_state(s.conn, p["name"]) or "no image yet"
        print(f"{p['name']}, {st}")
    return 0


def template_step(p):
    """bastion template T: Windows Setup in tpl-T, step by step: its Windows
    .iso copied in place from ~/Downloads by make-disk when it is not there,
    tpl-T defined when it is not, the firewall-vm warning, its console, its
    start with Space pressed once a second for 30 seconds for "Press any key
    to boot from CD or DVD" when it does not run, the wait."""
    name = p["name"]
    if os.path.exists(p["sealed"]):
        print(f"STOP: {name} is sealed; {CFG['command']} makes its workstations.")
        return 1
    made = False
    if not os.path.exists(p["iso"]):
        # Files beginning with a dot are not matched, as in the shell
        # (CPython 3.13 Doc/library/glob.rst 32-34, escape 119).
        pattern = os.path.join(os.path.expanduser("~"), "Downloads", f"*{glob.escape(p['download'])}*.iso")
        found = sorted(glob.glob(pattern))
        if not found:
            print(f"STOP: no .iso with {p['download']} in its name in Downloads.")
            return 1
        if len(found) > 1:
            print(f"STOP: more than one .iso with {p['download']} in its name in Downloads: {', '.join(found)}")
            return 1
        print(f"Copying {os.path.basename(found[0])} (a few minutes) ...", flush=True)
        rc, _ = run_step(None, "make-disk", [p["t"], found[0]])
        if rc:
            print("STOP: make-disk failed (lines above).")
            return 1
        os.remove(found[0])
        made = True
    conn = connect()
    if vm_state(conn, name) is None:
        try:
            define_template(p, made)
        except libvirt.libvirtError as e:
            print(e)
        if vm_state(conn, name) is None:
            print(f"STOP: {name} is not defined (the lines of {CFG['command']} template above).")
            return 1
        write_copy()
    warning = firewall_warning()
    if warning:
        print(warning, flush=True)
    open_console(name)
    if vm_state(conn, name) != VIRSH_STATES[libvirt.VIR_DOMAIN_RUNNING]:
        time.sleep(5)
        dom = conn.lookupByName(name)
        try:
            dom.create()
        except libvirt.libvirtError as e:
            print(f"STOP: {name} does not start: {e}.")
            return 1
        # libvirt's send-key, as virsh send-key sends it: the Linux code set,
        # no hold time (tools/virsh-domain.c 9069-9079, 9112); a refused
        # press is passed over.
        for _ in range(30):
            time.sleep(1)
            try:
                dom.sendKey(libvirt.VIR_KEYCODE_SET_LINUX, 0, [KEY_SPACE], 1, 0)
            except libvirt.libvirtError:
                pass
    return wait_off(conn, name, None)


def seal_step(p):
    """bastion seal T: when tpl-T is not sealed, the checks, then its sealed
    mark written by template-seal; then tpl-T undefined as bastion seal
    undefines it, when it is still defined."""
    name = p["name"]
    conn = connect()
    if not os.path.exists(p["sealed"]):
        st = vm_state(conn, name)
        if st is None:
            print(f"STOP: there is no {name} yet: {CFG['command']} template {p['t']}")
            return 1
        off = VIRSH_STATES[libvirt.VIR_DOMAIN_SHUTOFF]
        if st != off:
            print(f"STOP: {name} is '{st}', not '{off}'.")
            return 1
        # Its disk as du -k counts it: the blocks allocated, in 512-byte
        # units (CPython 3.13 Doc/library/os.rst 3189-3191; coreutils 9.11
        # src/du.c 638-640 with gnulib's lib/stat-size.h 79, 83-86), shown in
        # KiB rounded up (du.c 854-856, gnulib's lib/human.h 53). More than
        # 6000000 KiB is an installed Windows.
        if -(-os.stat(p["file"]).st_blocks * 512 // 1024) <= 6000000:
            print(f"STOP: Windows is not installed in {name}.")
            return 1
        rc, _ = run_step(None, "template-seal", [p["t"]])
        if rc:
            print(f"STOP: cannot mark {name} sealed.")
            return 1
    if vm_state(conn, name) is not None:
        try:
            seal_template(conn, p)
        except libvirt.libvirtError as e:
            print(e)
            print(f"STOP: {CFG['command']} seal {p['t']} failed (lines above).")
            return 1
        write_copy()
    print(f"{name} is sealed: {CFG['command']} makes workstations from it.")
    return 0


def start_step(name, first):
    """bastion start and bastion first: NAME started when it does not run, by the
    start of the start screen without its Enter; then its window, the
    looking-glass window at a start of a VM whose definition holds the glass
    block, the console otherwise; then the wait."""
    cmd = "first" if first else "start"
    s = State()
    v = s.vm(name)
    if v is None:
        print(f"STOP: no workstation '{name}' ({CFG['command']} list shows them).")
        return 1
    warning = firewall_warning()
    if warning:
        print(warning, flush=True)
    if vm_state(s.conn, name) != VIRSH_STATES[libvirt.VIR_DOMAIN_RUNNING]:
        refusals, pins, lines, vsock = start_plan(s, v, first)
        if refusals:
            print(f"{name} cannot start now:\n" + "\n".join(refusals))
            print(f"STOP: {name} is not started (the lines of {CFG['command']} {cmd} above).")
            return 1
        print("\n".join(lines), flush=True)
        print(f"starting {name} ...", flush=True)
        station_follows(None, v)
        write_copy()
        try:
            start_vm(s.conn, s.host, name, pins, vsock, first)
        except libvirt.libvirtError as e:
            print(f"{name} did not start: {e}\nUpload: journalctl -u libvirtd -b --no-pager | tail -n 40")
            print(f"STOP: {name} is not started (the lines of {CFG['command']} {cmd} above).")
            return 1
    glass = glass_command(v) if v.glass and not first else None
    if not glass:
        open_console(name)
    return wait_off(s.conn, name, glass)


def resolution_step(name):
    """bastion resolution NAME: the screen size NAME's station in
    networks.json holds as its resolution, or follows when it holds none or
    NAME has no station; presets/attach.sh writes the answer onto the stick
    for the presets module 96-resolution."""
    nets, error = read_networks_safe()
    if error:
        print(f"STOP: networks.json cannot be read ({error}).")
        return 1
    print(nets["stations"].get(name, {}).get("resolution", "follows"))
    return 0


def exchange_files_step(folder):
    """bastion exchange-files DIR: DIR/MODULE made, MODULE the presets
    module's word (host-networks.nix's exchange, handed over in the
    settings), holding the settings' store folder of the viosock files
    whole, copied file by file without the store's read-only modes so the
    copy can be removed; the exchange key's public half, the key's file name
    and .pub (OpenSSH V_10_5_P1 ssh-keygen.1 218-222) in the folder of
    networks.json, where broker-vm's key unit copies it; and the words file
    MODULE.json, every word the module reads: the group's account, folder,
    inbox-folder, outbox-folder, bridge-folder and module-lines under the
    same keys, the command's name as command and the public half's file
    name as public-key. presets/attach.sh puts DIR's content onto the stick.
    A missing public half stops it, nothing made; nothing is printed when
    it is done."""
    ex = CFG["exchange"]
    public_key = os.path.basename(ex["key"]) + ".pub"
    public_path = os.path.join(os.path.dirname(CFG["networksFile"]), public_key)
    if not os.path.isfile(public_path):
        print(f"STOP: {public_path} is not there: the keys are made at {CFG['brokerVm']}'s first start.")
        return 1
    out = os.path.join(folder, ex["module"])
    os.makedirs(out)
    store = CFG["viosock"]
    for top, _, files in os.walk(store):
        here = os.path.join(out, os.path.relpath(top, store))
        os.makedirs(here, exist_ok=True)
        for f in files:
            shutil.copyfile(os.path.join(top, f), os.path.join(here, f))
    shutil.copyfile(public_path, os.path.join(out, public_key))
    words = {k: ex[k] for k in ("account", "folder", "inbox-folder", "outbox-folder", "bridge-folder",
                                "module-lines")}
    words["command"] = CFG["command"]
    words["public-key"] = public_key
    with open(os.path.join(out, ex["module"] + ".json"), "w", encoding="ascii", newline="\n") as f:
        f.write(json.dumps(words, indent=2) + "\n")
    return 0


def main():
    with open(sys.argv[1]) as f:
        CFG.update(json.load(f))
    args = sys.argv[2:]
    names = " or ".join(p["t"] for p in CFG["templates"])
    command = CFG["command"]
    ex = CFG["exchange"]
    if not args:
        Bastion().run()
    elif args == ["list"]:
        sys.exit(list_step())
    elif args[0] in ("template", "seal") and len(args) == 2:
        p = template_of(args[1])
        if p is None:
            print(f"STOP: write {names} after {command} {args[0]}.")
            sys.exit(1)
        sys.exit(template_step(p) if args[0] == "template" else seal_step(p))
    elif args[0] in ("start", "first") and len(args) == 2:
        sys.exit(start_step(args[1], args[0] == "first"))
    elif args[0] == "console" and len(args) == 2:
        open_console(args[1])
    elif args[0] == "resolution" and len(args) == 2:
        sys.exit(resolution_step(args[1]))
    elif args[0] == ex["exchange-files"] and len(args) == 2:
        sys.exit(exchange_files_step(args[1]))
    elif args[0] == ex["send"] and len(args) == 4:
        sys.exit(run_step(None, ex["step"], args)[0])
    elif args[0] == ex["transfers"] and len(args) <= 2:
        sys.exit(run_step(None, ex["step"], [ex["transfers"], "", *args[1:]])[0])
    elif args[0] == ex["clean"] and len(args) == 2:
        sys.exit(run_step(None, ex["step"], args)[0])
    else:
        print(f"{command}, the status screen, then the VMs, the networks, the devices, looking-glass and "
              f"{ex['section']}\n"
              f"{command} list, every VM and template, its state, its disk, its card\n"
              f"{command} template T, Windows Setup in the template tpl-T (T: {names})\n"
              f"{command} seal T, after Sysprep: tpl-T sealed, {command} makes VMs from it\n"
              f"{command} first NAME, the first start of NAME, without network\n"
              f"{command} start NAME, starts NAME and shows it\n"
              f"{command} console NAME, the console window of NAME\n"
              f"{command} resolution NAME, the size NAME's Windows is locked at, or follows\n"
              f"{command} {ex['exchange-files']} DIR, the files the presets module {ex['module']} sets the "
              f"exchange up with, into DIR/{ex['module']}\n"
              f"{command} {ex['send']} FROM FILE TO\n"
              f"{command} {ex['transfers']} [NAME]\n"
              f"{command} {ex['clean']} NAME\n"
              f"{command} template, first and start run until the VM is off, meanwhile the host does not go "
              "to sleep by itself. Never close the lid then.")
        sys.exit(1)


if __name__ == "__main__":
    main()
