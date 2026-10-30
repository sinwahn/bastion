from system.errors import FileFailed


class NixDomains:
    """The domains Nix writes, each rewritten by Nix at every boot."""

    # A machine's own module may define VMs: the <name> of each xml file one
    # folder below /etc whose root element is a libvirt <domain>. libvirt
    # keeps its own definitions under /var/lib/libvirt, out of reach.

    def __init__(self, files, log):
        self.files = files
        self.log = log

    def names(self):
        names = set()
        for path in self.files.matching(self.kDefinitions):
            try:
                root = self.files.xml_root(path)
            except FileFailed as failure:
                self.log.note(f"{path} is skipped: {failure}")
                continue
            if root.tag == "domain" and root.findtext("name"):
                names.add(root.findtext("name"))
        return names

    files = None
    log = None
    kDefinitions = "/etc/*/*.xml"
