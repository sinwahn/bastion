import os


class GlassClientPlaces:
    """Where the looking-glass client reads its files."""

    # The looking-glass client the host runs is gnif/LookingGlass at
    # cdba29f2f6bcae3ded26369fc231a067cbca3752 (modules/host/looking-glass.nix);
    # the lines below name its files. It reads /etc's file first; the per-user
    # file is read later and overrides it (client/src/config.c 572-623).

    def system_file(self):
        return self.kSystemFile

    def own_file(self):
        """The per-user file, by the client's rule."""
        # $XDG_CONFIG_HOME/looking-glass/client.ini, or
        # ~/.config/looking-glass/client.ini when XDG_CONFIG_HOME is not set,
        # home from HOME, else from the password entry
        # (common/src/platform/linux/paths.c 61-71, client/src/main.c 4310,
        # client/src/config.c 607); expanduser takes home the same way.
        base = os.environ.get("XDG_CONFIG_HOME")
        if base is None:
            base = os.path.join(os.path.expanduser("~"), ".config")
        return os.path.join(base, "looking-glass", "client.ini")

    kSystemFile = "/etc/looking-glass-client.ini"
