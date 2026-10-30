import copy

from model.RestoreResult import RestoreResult


class NetworksCopy:
    """The copy of the live data file in the copy folder, and the live data file after a restore."""

    def copied(self, live, old, defined):
        """The live file, plus each station the old copy holds for a VM not defined now, with the network it names."""
        # defined: the names of every VM libvirt holds. Such a station is the
        # copy's own even when the live file holds that name, since no VM
        # stands behind the live entry; a VM defined now gets the live entry,
        # and a network the live file holds keeps the live entry.
        result = copy.deepcopy(live)
        for name, station in old.stations.items():
            if name in defined:
                continue
            result.stations[name] = copy.deepcopy(station)
            if self._lacks(result, old, station.network):
                self._add_network(result, old, station.network)
        return result

    def restored(self, live, saved, names):
        """The live file after the VMs names are restored: each one's station from the copy, its network added when missing."""
        # A live entry of the same name is replaced, since no VM stands behind
        # it; a network the live file holds is kept as it is; every other
        # station is kept as it is.
        result = RestoreResult()
        result.content = copy.deepcopy(live)
        for name in names:
            if name not in saved.stations:
                continue
            station = saved.stations[name]
            result.content.stations[name] = copy.deepcopy(station)
            result.stations.append(name)
            if self._lacks(result.content, saved, station.network):
                self._add_network(result.content, saved, station.network)
                result.networks.append(station.network)
        return result

    def _lacks(self, content, source, network):
        return network not in content.networks and network in source.networks

    def _add_network(self, content, source, network):
        content.networks[network] = copy.deepcopy(source.networks[network])
