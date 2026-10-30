class GlassCommand:
    """The looking-glass client's command for a VM."""

    # With win:setGuestRes=no when its station holds a resolution, so resizing
    # the window never asks Windows to take its size (the option,
    # client/src/config.c 218-224; the release key with = still asks,
    # client/src/keybind.c 133-151; the command line's form
    # section:name=value, doc/usage.rst 111-117; the client reads its command
    # line after /etc's file and the per-user file, so it wins over both,
    # config.c 625-627).

    def words(self, vm):
        if vm.has_station and "resolution" in vm.station.keys:
            return [self.kClient, "win:setGuestRes=no"]
        return [self.kClient]

    kClient = "looking-glass-client"
