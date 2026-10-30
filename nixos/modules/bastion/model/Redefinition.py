from model.DefinitionFragments import DefinitionFragments


class Redefinition:
    """A VM's stored definition changed and saved, and named among this run's changes."""

    def __init__(self, libvirt, changes):
        self.libvirt = libvirt
        self.changes = changes

    def apply(self, name, change):
        """The definition changed by change(root) and saved."""
        root = self.libvirt.definition(name)
        change(root)
        self.libvirt.define(self.kFragments.text(root))
        self.changes.add(name)

    libvirt = None
    changes = None
    kFragments = DefinitionFragments()
