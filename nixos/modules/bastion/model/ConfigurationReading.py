from model.AnswerPlace import AnswerPlace
from model.Cable import Cable
from model.Configuration import Configuration
from model.ExchangeWords import ExchangeWords
from model.ProgramPaths import ProgramPaths
from model.ServiceVm import ServiceVm
from model.Template import Template
from model.Uplink import Uplink


class ConfigurationReading:
    """The settings file's values, read into the configuration."""

    def __init__(self, values):
        self.values = values

    def read(self):
        configuration = Configuration()
        self._read_places(configuration)
        self._read_vms(configuration)
        self._read_networks(configuration)
        self._read_checks(configuration)
        configuration.exchange = self._exchange(self.values["exchange"])
        configuration.programs = self._programs()
        return configuration

    def _read_places(self, configuration):
        values = self.values
        configuration.command = values["command"]
        configuration.uri = values["uri"]
        configuration.images_folder = values["images"]
        configuration.retired_folder = values["retired"]
        configuration.virtio_iso = values["virtioIso"]
        configuration.live_data_file = values["networksFile"]
        configuration.copy_folder = values["copyDir"]
        configuration.viosock_folder = values["viosock"]
        configuration.virtio_drivers_folder = values["virtioDrivers"]
        configuration.transfers_lines = values["transfersLines"]

    def _read_vms(self, configuration):
        values = self.values
        configuration.host_share.threads = values["share"]["threads"]
        configuration.host_share.ram = values["share"]["ram"]
        configuration.host_share.disk = values["share"]["disk"]
        configuration.pick_steps.ram = values["steps"]["ram"]
        configuration.pick_steps.disk = values["steps"]["disk"]
        configuration.service_vms = [self._service_vm(entry) for entry in values["services"]]
        configuration.templates = [self._template(entry) for entry in values["templates"]]
        configuration.names_in_use = values["namesInUse"]
        configuration.name_maximum = values["nameMax"]
        configuration.refused_prefixes = values["refusedPrefixes"]
        configuration.vsock_first = values["vsockFirst"]

    def _read_networks(self, configuration):
        values = self.values
        configuration.switch = values["switch"]
        configuration.host_ip = values["hostAddress"]
        configuration.host_port = values["hostPort"]
        configuration.host_network_names = values["hostNetworkNames"]
        configuration.firewall_vm = values["firewallVm"]
        configuration.wifi_vm = values["wifiVm"]
        configuration.broker_vm = values["brokerVm"]
        configuration.wifi_uplink = values["wifiUplink"]
        configuration.cables = [self._cable(entry) for entry in values["cables"]]
        configuration.uplinks = [self._uplink(entry) for entry in values["uplinks"]]
        configuration.reroute.through = values["reroute"]["through"]
        configuration.reroute.direct = values["reroute"]["direct"]
        configuration.preferred_uplink = values["prefer"]

    def _read_checks(self, configuration):
        configuration.internet_target = self.values["internet"]
        configuration.internet_seconds = self.values["internetTimeout"]
        configuration.firewall_check = self._answer_place(self.values["firewallCheck"])
        configuration.wifi_check = self._answer_place(self.values["wifiCheck"])

    def _service_vm(self, entry):
        service = ServiceVm()
        service.name = entry["name"]
        service.threads = entry["vcpu"]
        service.memory = entry["mem"]
        service.unit = entry["unit"]
        service.meaning = entry["meaning"]
        return service

    def _template(self, entry):
        template = Template()
        template.word = entry["t"]
        template.name = entry["name"]
        template.iso = entry["iso"]
        template.download = entry["download"]
        template.disk = entry["disk"]
        template.memory = entry["memory"]
        template.vcpus = entry["vcpus"]
        template.win11 = entry["win11"]
        template.uuid = entry["uuid"]
        template.file = entry["file"]
        template.sealed = entry["sealed"]
        return template

    def _cable(self, entry):
        cable = Cable()
        cable.name = entry["name"]
        cable.switch = entry["switch"]
        return cable

    def _uplink(self, entry):
        uplink = Uplink()
        uplink.name = entry["name"]
        uplink.device = entry["device"]
        uplink.kind = entry["kind"]
        uplink.is_cable = entry["cable"]
        uplink.is_path = entry["path"]
        return uplink

    def _answer_place(self, entry):
        place = AnswerPlace()
        place.cid = entry["cid"]
        place.port = entry["port"]
        return place

    def _exchange(self, entry):
        words = ExchangeWords()
        words.section = entry["section"]
        words.section_key = entry["section-key"]
        words.sends_to = entry["sends-to"]
        words.sends_to_label = entry["sends-to-label"]
        words.nothing_listed = entry["none"]
        words.retired_mark = entry["retired"]
        words.send = entry["send"]
        words.send_action = entry["send-action"]
        words.transfers = entry["transfers"]
        words.clean = entry["clean"]
        words.clean_action = entry["clean-action"]
        words.outbox_folder = entry["outbox-folder"]
        words.usage_verb = entry["verbs"]["usage"]
        words.usage_line = entry["lines"]["usage"]
        words.step = entry["step"]
        words.key = entry["key"]
        words.module = entry["module"]
        words.exchange_files = entry["exchange-files"]
        words.module_words = {key: entry[key] for key in self.kModuleKeys}
        return words

    def _programs(self):
        programs = ProgramPaths()
        programs.nmcli = self.values["nmcli"]
        programs.ip = self.values["ip"]
        programs.socat = self.values["socat"]
        programs.bridge = self.values["bridge"]
        programs.systemctl = self.values["systemctl"]
        programs.privileged = self.values["privileged"]
        return programs

    values = {}
    # The words the presets module of the exchange reads, under the same keys.
    kModuleKeys = ("account", "folder", "inbox-folder", "outbox-folder", "bridge-folder", "module-lines")
