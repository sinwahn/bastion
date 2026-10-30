from model.glass_options.KeyOption import KeyOption
from model.glass_options.YesNoOption import YesNoOption


class GlassSettings:
    """The looking-glass window's settings the looking-glass section sets, each under its label."""

    def __init__(self, system_file, own_file):
        self.system_file = system_file
        self.own_file = own_file

    def labels(self):
        return list(self.kOptions)

    def option(self, label):
        return self.kOptions[label]

    def read(self):
        """The settings as the client reads them, {label: value}: the per-user file's line, else /etc's file's, else the client's default."""
        system = self.system_file.options()
        own = self.own_file.options()
        settings = {}
        for label, option in self.kOptions.items():
            section, name = option.section().lower(), option.option().lower()
            value = own.get(section, {}).get(name, system.get(section, {}).get(name, option.default()))
            settings[label] = option.shown(value)
        return settings

    def write(self, label, value):
        option = self.kOptions[label]
        self.own_file.write_option(option.section(), option.option(), value)

    system_file = None
    own_file = None
    kOptions = {"release key": KeyOption(), "full screen": YesNoOption()}
