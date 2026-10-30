# A cable's card is the host's or, rerouted through the firewall VM, the
# Wi-Fi VM's: that VM's QEMU runs as the group of microvm.nix's VM units, so
# that group may open each cable's card, to hold it while the cable is
# rerouted.
{ config, lib, pkgs, ... }:

let
  wifiVm = (import ../isolation/host-networks.nix).vms.wifi-vm;
  inherit (import ./uplink-roles.nix { inherit lib; }) cables cableNames;
  inherit (import ../service-vms/service-vm-locations.nix { inherit config lib; }) controlSocket;
  uplinkFunctions = import ./uplink-functions.nix { inherit config lib pkgs; };
  udevRule = import ../host/udev-rule.nix { inherit lib; };
in
{
  services.udev.extraRules = lib.concatStrings (lib.mapAttrsToList (n: u: udevRule
    [ [ "SUBSYSTEM" "usb" ] [ "ENV{DEVTYPE}" "usb_device" ] [ "ATTR{idVendor}" u.vendor ] [ "ATTR{idProduct}" u.product ] ]
    [ [ "GROUP" config.systemd.services."microvm@".serviceConfig.Group ] [ "MODE" "0660" ] ]) cables);

  # The Wi-Fi VM's QEMU holds every cable's card from its start; this gives
  # back the card of each cable whose route is direct to the host, whose
  # host profile then connects by itself again.
  systemd.services.uplinks-reroute = {
    description = "Each cable of uplinks.nix on its route when ${wifiVm} starts";
    wantedBy = [ "microvm@${wifiVm}.service" ];
    after = [ "microvm@${wifiVm}.service" "NetworkManager.service" ];
    partOf = [ "microvm@${wifiVm}.service" ];
    path = [ pkgs.coreutils pkgs.gnugrep ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      . ${uplinkFunctions}
      # QEMU's control socket appears once the VM's QEMU runs.
      for i in $(seq 1 60); do
        if [ -S ${controlSocket wifiVm} ]; then break; fi
        sleep 1
      done
      rc=0
      for n in ${toString cableNames}; do
        if [ "$(route "$n")" = vm ]; then
          hand "$n" || { echo "${wifiVm}'s QEMU did not take $n's card; the reason stands above."; rc=1; }
        else
          take "$n" || { echo "${wifiVm}'s QEMU did not give $n's card back; the reason stands above."; rc=1; }
        fi
      done
      exit $rc
    '';
  };
}
