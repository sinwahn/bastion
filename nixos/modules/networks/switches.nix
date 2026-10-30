{ lib, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  switches = hostNetworks.switches;
  inherit (import ./station-roles.nix { inherit lib; }) stations vmStations hostEntry;
  deviceNameAssertion = import ./device-name-assertion.nix { inherit lib; };
  # The port end of the host's cable is attached by NixOS's bridge setup,
  # so a re-made workstations' switch gets it back.
  switchMembers = {
    ${switches.wifi-link} = [ ];
    ${switches.workstations} = [ hostEntry ];
  };
in
{
  assertions = lib.mapAttrsToList (n: s: deviceNameAssertion n (length: max:
    "modules/isolation/stations.nix: the station ${n} has a name of ${length} characters; a station's name is its cable's name, at most ${max} characters."
  )) stations ++ map (c: deviceNameAssertion c.name (length: max:
    "modules/isolation/host-networks.nix: the cable ${c.name} has a name of ${length} characters; a cable's name is its device's name on the host, at most ${max} characters."
  )) (lib.attrValues hostNetworks.cables);

  networking.bridges = lib.mapAttrs (s: members: { interfaces = members; }) switchMembers;
  # The switches carry no address of the host's own networking, so nothing
  # in the dependency graph activates their bridge services and the devices
  # would never be made.
  systemd.services = lib.mapAttrs' (s: members: lib.nameValuePair "${s}-netdev" {
    wantedBy = [ "multi-user.target" ];
  }) switchMembers;

  networking.networkmanager.unmanaged =
    map (n: "interface-name:${n}") (lib.attrValues switches ++ lib.attrNames vmStations
      ++ map (c: c.name) (lib.attrValues hostNetworks.cables))
    ++ [ "interface-name:tap*" "interface-name:vnet*" "interface-name:virbr*" "interface-name:${hostEntry}" ];

  virtualisation.libvirtd.allowedBridges = [ "virbr0" ] ++ lib.attrValues switches;
}
