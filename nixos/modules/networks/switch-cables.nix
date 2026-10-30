# Not a module: the cables that belong on a switch, imported by
# networks-apply.nix and gate.nix.
{ lib }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  switches = hostNetworks.switches;
  inherit (import ./station-roles.nix { inherit lib; }) hostEntry;
in
s: lib.optional (s == switches.workstations) hostEntry ++ map (c: c.name)
  (lib.filter (c: switches.${c.switch} == s) (lib.attrValues hostNetworks.cables))
