# The example of stations.nix: in a machine's private clone, copy it to
# stations.nix beside it and write the machine's own stations (README.md).
# Every machine behind the firewall VM, with its internet rule (rules per
# workstation, all in this repository). Not a module: host.nix,
# gateway.nix and bastion.nix read it.
#   ip    its address on the workstations' switch (host-networks.nix); the
#         firewall VM gives it to mac.
#   rule  "open"    the whole internet; every new connection and every
#                   name it asks for is logged.
#         "listed"  only the names in "names" and their subdomains;
#                   everything else is refused and logged.
#         "none"    no internet; every try is logged.
# Its cable on that switch takes its name here; host.nix refuses a name
# longer than a network device name may be.
# The stations that have a mac are written into the live data file of
# host-networks.nix by networks-apply (host.nix) when that file is missing;
# from then on the guard and the firewall VM take their rules from the file,
# not from here. The host's entry stays here: its own line in the firewall
# VM and its address on the host.
{
  host = { ip = "10.200.0.2"; rule = "open"; };
  tpl-win10 = { ip = "10.200.0.201"; mac = "52:54:00:00:00:01"; rule = "open"; };
  tpl-win11 = { ip = "10.200.0.202"; mac = "52:54:00:00:00:02"; rule = "open"; };
  example = { ip = "10.200.0.101"; mac = "52:54:00:00:00:03"; rule = "open"; };
}
