# Not a module: the stations of stations.nix by their role, derived once
# here and imported by the modules that need them.
{ lib }:

let
  stations = import ../isolation/stations.nix;
  hostStations = lib.filterAttrs (n: s: !(s ? mac)) stations;
  # A cable takes the name of the machine it belongs to, so the port end of
  # the host's cable on the workstations' switch is named after this entry.
  hostEntry = lib.head (lib.attrNames hostStations);
in
{
  inherit stations hostStations hostEntry;
  hostIp = stations.${hostEntry}.ip;
  vmStations = lib.filterAttrs (n: s: s ? mac) stations;
}
