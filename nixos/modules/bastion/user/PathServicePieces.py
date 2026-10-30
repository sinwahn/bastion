from user.UplinkStatus import UplinkStatus


class PathServicePieces:
    """The path check's pieces read from the service VMs: their units, firewall-vm's leg, wifi-vm's way out and the internet."""

    def __init__(self, access, pieces):
        self.access = access
        self.pieces = pieces
        self.configuration = access.configuration

    def add_service(self, name):
        """A service VM's unit, as the status screen reads it."""
        service = self._service(name)
        if self.access.service_units.is_active(service.unit):
            self.pieces.add_yes(name, "running")
        else:
            self.pieces.add(name, "not running", f"{name} is not running: {service.meaning}. Do: sudo systemctl start {service.unit}")

    def add_leg(self, name, network, facts):
        """firewall-vm's leg on the network and the VM's line (firewall-check)."""
        firewall = self.configuration.firewall_vm
        subject = f"{firewall}'s leg {network}"
        rule_again = f"Do: save {name}'s internet rule again in the networks section"
        if facts.station_unknown:
            fact = f"{name} is not in networks.json"
            self.pieces.add(subject, fact, f"{subject}: {fact}: firewall-apply did not load it. {rule_again}")
        elif not facts.has_leg or len(facts.line) < 3:
            fact = f"cannot be read: {firewall} does not answer"
            self.pieces.add(subject, fact, f"{subject}: {fact}. {self._restart(firewall)}")
        else:
            loaded, rule, count = facts.line[:3]
            fact = f"{facts.leg[1]}, {name}'s line: {self._line_text(loaded, rule)}, {self._rule_text(rule, count)}"
            loaded_well = facts.leg[1:2] == ["up"] and loaded == rule
            self.pieces.add(subject, fact, "" if loaded_well else f"{subject}: {fact}: firewall-apply did not load it. {rule_again}")

    def add_wifi(self):
        """wifi-vm's way out (wifi-check): its Wi-Fi, and each cable rerouted through firewall-vm, whose card it holds then."""
        # While one of them is wifi-vm's way out, another one not connected is
        # no break.
        facts = self.access.wifi_check.read(self.configuration.internet_seconds)
        status = UplinkStatus(self.access)
        rerouted = [uplink.name for uplink in self.configuration.uplinks if uplink.is_cable and status.route(uplink) == "vm"]
        out = facts.route[0] if facts.route and facts.route[0] not in ("none", "other") else ""
        self._add_card(facts.card, out, rerouted)
        for name in rerouted:
            self._add_rerouted(name, facts, out)

    def add_internet(self, facts):
        """Internet from firewall-vm (firewall-check)."""
        firewall = self.configuration.firewall_vm
        subject = f"internet from {firewall}"
        if not facts.has_internet:
            fact = f"cannot be read: {firewall} does not answer"
            self.pieces.add(subject, fact, f"{subject}: {fact}. {self._restart(firewall)}")
        elif facts.internet[:1] == ["yes"]:
            self.pieces.add_yes(subject, "")
        else:
            fact = f"no answer within {self.configuration.internet_seconds} seconds"
            self.pieces.add(subject, fact, f"{subject}: {fact}. {self._gate_wifi()}")

    def _add_card(self, card, out, rerouted):
        wifi = self.configuration.wifi_vm
        meaning = self._service(wifi).meaning
        subject = f"{wifi}'s Wi-Fi"
        if card and card[1] == "connected":
            self.pieces.add_yes(subject, f"connected to {card[2]}" if len(card) > 2 else "connected")
        elif card and out in rerouted:
            self.pieces.add_yes(subject, f"not connected, {wifi} goes out over {out}")
        elif card:
            self.pieces.add(subject, "not connected", f"{wifi}'s Wi-Fi is not connected: {meaning}. {self._gate_wifi()}")
        else:
            self.pieces.add(subject, f"cannot be read: {wifi} does not answer",
                            f"{wifi}'s Wi-Fi cannot be read: {meaning}. {self._restart(wifi)}")

    def _add_rerouted(self, name, facts, out):
        wifi = self.configuration.wifi_vm
        meaning = self._service(wifi).meaning
        subject = f"{wifi}'s cable {name}"
        if name not in facts.uplinks:
            self.pieces.add(subject, f"cannot be read: {wifi} does not answer",
                            f"{subject}: cannot be read: {wifi} does not answer. {self._restart(wifi)}")
            return
        fact = facts.uplinks[name]
        if fact.state == "up" and fact.permission == "allowed":
            self.pieces.add_yes(subject, "connected, allowed")
            return
        words = "not connected" if fact.state != "up" else "connected, not allowed"
        if out and out != name:
            self.pieces.add_yes(subject, f"{words}, {wifi} goes out over {out}")
        elif fact.state == "up":
            self.pieces.add(subject, words, f"{subject}: {words}: {meaning}. Do: gate {name}")
        else:
            self.pieces.add(subject, words, f"{subject}: {words}: {meaning}. "
                                            f"Do: check that the cable is plugged in, or gate reroute {name} direct to host")

    def _line_text(self, loaded, rule):
        if loaded == rule:
            return "none" if rule == "none" else "loaded"
        if loaded == "none":
            return "not loaded"
        return f"loaded as {loaded}"

    def _rule_text(self, rule, count):
        return {"open": "rule open", "listed": f"rule listed, {count} names",
                "none": "rule none: refused by its rule"}.get(rule, f"rule {rule}")

    def _service(self, name):
        return next(service for service in self.configuration.service_vms if service.name == name)

    def _restart(self, name):
        """An answer point that does not answer: its VM restarted."""
        return f"Do: sudo systemctl restart {self._service(name).unit}"

    def _gate_wifi(self):
        return f"Do: gate {self.configuration.wifi_uplink}"

    access = None
    pieces = None
    configuration = None
