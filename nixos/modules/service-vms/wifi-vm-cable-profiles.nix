# Inside the Wi-Fi VM each cable's profile, named after its entry, is made
# on its card at every start, carrying nothing until gate allows it; what
# gate set in it stays.
{ lib, pkgs, ... }:

let
  wifiVm = (import ../isolation/host-networks.nix).vms.wifi-vm;
  inherit (import ../networks/uplink-roles.nix { inherit lib; }) uplinkList cables;
  inherit (import ./wifi-vm-cards.nix { inherit lib; }) cableCardName;
  deviceNameAssertion = import ../networks/device-name-assertion.nix { inherit lib; };
  otherMetric = toString uplinkList.metric.others;
  ensureInside = pkgs.writeShellScript "uplinks-ensure" ''
    set -u
    ${lib.concatMapStrings (n: ''
    nmcli connection show ${n} >/dev/null 2>&1 \
      || nmcli connection add type ethernet con-name ${n} connection.interface-name ${cableCardName n} connection.autoconnect yes ipv4.method auto ipv4.never-default yes ipv6.never-default yes ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes ipv4.route-metric ${otherMetric} ipv6.route-metric ${otherMetric} >/dev/null
    '') (lib.attrNames cables)}'';
in
{
  assertions = map (n: deviceNameAssertion (cableCardName n) (length: max:
    "modules/isolation/uplinks.nix: inside ${wifiVm} the cable ${n}'s card is named ${cableCardName n}, ${length} characters; a network device's name is at most ${max} characters."
  )) (lib.attrNames cables);

  microvm.vms.${wifiVm}.config = {
    networking.networkmanager.settings.main.no-auto-default =
      lib.concatMapStringsSep ";" (n: "interface-name:${cableCardName n}") (lib.attrNames cables);
    systemd.services.uplinks-ensure = {
      description = "The profiles of the cables of uplinks.nix this VM may hold";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" ];
      path = [ pkgs.networkmanager ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = "${ensureInside}";
    };
  };
}
