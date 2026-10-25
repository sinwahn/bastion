# The example of uplinks.nix: in a machine's private clone, copy it to
# uplinks.nix beside it and write the machine's own cards (README.md).
# The host's uplinks: the explicit allowance list. Not a module: host.nix
# and net.nix read it. Each uplink is a NetworkManager profile of the host,
# named after its entry. "gate NAME" allows it to carry the host's default
# route and DNS, "gate NAME off" withdraws that (the profile and its link
# stay up), "gate prefer NAME" chooses which allowed uplink carries the
# traffic when both are up. The unit uplinks-ensure (at every start) and
# gate (on every run) make the profiles from this list and keep them in
# step with it.
#   prefer   the uplink preferred at the start; "gate prefer" changes it.
#   metric   the route metrics gate gives: "preferred" to the preferred
#            uplink, "others" to every other one (the lowest metric
#            carries the traffic).
#   uplinks  one attribute set per uplink:
#     kind     "vm": the path through the two service VMs (host-networks.nix),
#              "device" the inner end of the host's cable on the
#              workstations' switch (host.nix makes the pair); "ethernet":
#              a cable on the host itself.
#     device   the host's interface the profile uses.
#     pci      the PCI address of the Wi-Fi card the Wi-Fi VM holds and
#     drivers  the kernel drivers that take it; the host never loads them.
#     prefix   the length of the host's address on device (the address is
#              the host's entry in stations.nix) and
#     gateway  the firewall VM's address there, also the host's DNS.
#     vendor   the card's USB vendor id and
#     product  its USB product id; the interface is named device by them.
# A machine's values are read from /sys/bus/pci/devices and
# /sys/bus/usb/devices.
{
  prefer = "ethernet";
  metric = { preferred = 100; others = 600; };
  uplinks = {
    wifi = {
      kind = "vm";
      device = "host-wifi";
      pci = "0000:00:00.0";
      drivers = [ "DRIVER" ];
      prefix = 24;
      gateway = "10.200.0.1";
    };
    # An ethernet card, on USB.
    ethernet = {
      kind = "ethernet";
      device = "host-ethernet";
      vendor = "0000";
      product = "0000";
    };
  };
}
