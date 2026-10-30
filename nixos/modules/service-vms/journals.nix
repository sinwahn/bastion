# The service VMs' journals, readable on the host with journalctl -m.
{ config, lib, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  inherit (import ./service-vm-locations.nix { inherit config lib; }) journalId journalFolder;
in
{
  systemd.tmpfiles.rules = map (v:
    "L+ /var/log/journal/${journalId v} - - - - ${journalFolder v}"
  ) (lib.attrValues hostNetworks.vms);
}
