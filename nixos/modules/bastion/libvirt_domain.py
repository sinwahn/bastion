# /etc/nixos/modules/bastion/libvirt_domain.py
# The system layer: one domain of libvirt's store, through libvirt-python.

import libvirt


class LibvirtDomain:
    """One domain of libvirt's store: its definitions, its disk's figures and
    the calls that start, stop and undefine it."""

    def __init__(self, domain):
        self.domain = domain

    def name(self):
        return self.domain.name()

    def definition(self):
        return self.domain.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)

    def live_definition(self):
        return self.domain.XMLDesc(0)

    def is_active(self):
        return bool(self.domain.isActive())

    def capacity(self, target):
        return self.domain.blockInfo(target)[0]

    def allocation(self, target):
        return self.domain.blockInfo(target)[1]

    def create(self):
        self.domain.create()

    def shut_down(self):
        self.domain.shutdown()

    def undefine_keeping_state(self):
        self.domain.undefineFlags(libvirt.VIR_DOMAIN_UNDEFINE_KEEP_NVRAM | libvirt.VIR_DOMAIN_UNDEFINE_KEEP_TPM)

    def press_key(self, code):
        # libvirt's send-key, as virsh send-key sends it: the Linux code set,
        # no hold time (tools/virsh-domain.c 9069-9079, 9112).
        self.domain.sendKey(libvirt.VIR_KEYCODE_SET_LINUX, 0, [code], 1, 0)

    def resize_disk(self, target, size):
        self.domain.blockResize(target, size, libvirt.VIR_DOMAIN_BLOCK_RESIZE_BYTES)
