import json

from model.IpRange import IpRange
from model.LiveDataFileContent import LiveDataFileContent
from model.NetworkEntry import NetworkEntry
from model.StationEntry import StationEntry


class LiveDataFormat:
    """The live data file's JSON read into its entries and written back byte for byte as networks-write writes it."""

    def __init__(self, destinations_key):
        self.destinations_key = destinations_key

    def parse(self, values):
        content = LiveDataFileContent()
        content.keys = list(values)
        content.networks = {name: self._network(entry) for name, entry in values.get("networks", {}).items()}
        content.stations = {name: self._station(entry) for name, entry in values.get("stations", {}).items()}
        content.others = {key: value for key, value in values.items() if key not in ("networks", "stations")}
        return content

    def render(self, content):
        return json.dumps(self.values(content), indent=2) + "\n"

    def values(self, content):
        rendered = {"networks": {name: self._entry_values(entry, self.kNetworkFields)
                                 for name, entry in content.networks.items()},
                    "stations": {name: self._station_values(entry) for name, entry in content.stations.items()}}
        return {key: rendered[key] if key in rendered else content.others[key] for key in content.keys}

    def _network(self, values):
        return self._entry(NetworkEntry(), values, self.kNetworkFields)

    def _station(self, values):
        entry = self._entry(StationEntry(), values, self._station_fields())
        if entry.ip is self.kJsonNull:
            entry.ip = IpRange.kNoneFree
        return entry

    def _entry(self, entry, values, fields):
        entry.keys = list(values)
        for key, value in values.items():
            if key in fields:
                setattr(entry, fields[key], value)
            else:
                entry.others[key] = value
        return entry

    def _station_values(self, entry):
        values = self._entry_values(entry, self._station_fields())
        # A station given no IP, its network's range being full, is written
        # with null, which networks-write refuses.
        if values.get("ip") == IpRange.kNoneFree:
            values["ip"] = self.kJsonNull
        return values

    def _entry_values(self, entry, fields):
        return {key: getattr(entry, fields[key]) if key in fields else entry.others[key] for key in entry.keys}

    def _station_fields(self):
        return dict(self.kStationFields, **{self.destinations_key: "destinations"})

    destinations_key = ""
    kJsonNull = None
    kNetworkFields = {"lane": "vlan_tag", "ip-range": "ip_range", "reach-each-other": "reach_each_other"}
    kStationFields = {"network": "network", "ip": "ip", "mac": "mac", "rule": "rule", "names": "names",
                      "resolution": "resolution"}
