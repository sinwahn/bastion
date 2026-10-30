from model.DefinitionFragments import DefinitionFragments
from model.SystemFailures import SystemFailures


class Redefinition:
    """A VM's stored definition changed and saved, and named among this run's changes."""

    def __init__(self, libvirt, changes):
        self.libvirt = libvirt
        self.changes = changes

    def apply(self, name, change):
        """The definition changed by change(root) and saved."""
        with self.kFailures.raised_as_model():
            root = self.libvirt.definition(name)
            change(root)
            self.libvirt.define(self.kFragments.text(root))
        self.changes.add(name)

    def saved_definition(self, name):
        """The definition as libvirt holds it now."""
        with self.kFailures.raised_as_model():
            return self.libvirt.definition(name)

    libvirt = None
    changes = None
    kFragments = DefinitionFragments()
    kFailures = SystemFailures()
