# Not a module: the uplinks whose way out the Wi-Fi VM may carry and the
# name each one's card takes inside it, derived once here.
{ lib }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  inherit (import ../networks/uplink-roles.nix { inherit lib; }) uplinkThroughVms cables;
  cableCardName = n: "${n}-card";
in
{
  inherit cableCardName;
  uplinksInside = [ uplinkThroughVms ] ++ lib.attrNames cables;
  cardNameInside = n: if n == uplinkThroughVms then hostNetworks.wifi-card else cableCardName n;
}
