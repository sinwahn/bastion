# Not a module: the uplinks of uplinks.nix by their role, derived once here
# and imported by the modules that need them.
{ lib }:

let
  uplinkList = import ../isolation/uplinks.nix;
  uplinks = uplinkList.uplinks;
  uplinksThroughVms = lib.filterAttrs (n: u: u ? gateway) uplinks;
  cables = lib.filterAttrs (n: u: u ? vendor) uplinks;
in
{
  inherit uplinkList uplinks uplinksThroughVms cables;
  uplinkNames = lib.attrNames uplinks;
  uplinkThroughVms = lib.head (lib.attrNames uplinksThroughVms);
  cableNames = lib.attrNames cables;
  pciCards = lib.filter (u: u ? pci) (lib.attrValues uplinks);
  hostCableInnerEnd = (lib.head (lib.attrValues uplinksThroughVms)).device;
  # On a cable the DNS is the one its DHCP server names.
  dnsOf = u: if u ? gateway then u.gateway else "";
  # udev applies .link files with or without systemd-networkd.
  cableLink = name: u: {
    matchConfig.Property = "ID_VENDOR_ID=${u.vendor} ID_MODEL_ID=${u.product}";
    linkConfig.Name = name;
  };
}
