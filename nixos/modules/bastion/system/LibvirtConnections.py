from system.LibvirtConnection import LibvirtConnection


class LibvirtConnections:
    """Fresh connections to libvirt's store at the settings' uri."""

    def __init__(self, uri, log):
        self.uri = uri
        self.log = log

    def open(self):
        connection = LibvirtConnection(self.uri, self.log)
        connection.open()
        return connection

    uri = ""
    log = None
