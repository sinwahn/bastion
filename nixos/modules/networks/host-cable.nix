# The host's cable on the workstations' switch is a veth pair made before
# the switch's unit, which is then the only maker of the switch. That unit
# is bound to the port end: were the pair deleted, it would stop and delete
# the switch, so the pair is never deleted.
{ lib, pkgs, ... }:

let
  switches = (import ../isolation/host-networks.nix).switches;
  inherit (import ./station-roles.nix { inherit lib; }) hostEntry;
  inherit (import ./uplink-roles.nix { inherit lib; }) hostCableInnerEnd;
in
{
  systemd.services."${hostEntry}-netdev" = {
    description = "The host's cable on ${switches.workstations}: ${hostEntry} on the bridge, ${hostCableInnerEnd} the host's";
    wantedBy = [ "${switches.workstations}-netdev.service" ];
    before = [ "${switches.workstations}-netdev.service" ];
    after = [ "network-pre.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      ip link show dev ${hostEntry} >/dev/null 2>&1 \
        || ip link add name ${hostEntry} type veth peer name ${hostCableInnerEnd}
    '';
  };
}
