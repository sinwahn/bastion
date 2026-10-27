# The example of uplinks.nix: in a machine's private clone, copy it to
# uplinks.nix beside it and write the machine's own cards (README.md).
# The host's uplinks: the explicit allowance list. Not a module: host.nix
# and net.nix read it. Each uplink is a NetworkManager profile of the host,
# named after its entry. "gate NAME" allows it to carry the host's default
# route and DNS, "gate NAME off" withdraws that (the profile and its link
# stay up), "gate prefer NAME" chooses which allowed uplink carries the
# traffic when both are up; "gate reroute NAME through firewall-vm" and
# "gate reroute NAME direct to host" move a cable's card between the Wi-Fi
# VM and the host (kind below). The unit uplinks-ensure (at every start)
# and gate (on every run) make the profiles from this list and keep them in
# step with it.
#   prefer   the uplink preferred at the start; "gate prefer" changes it.
#   metric   the route metrics gate gives: "preferred" to the preferred
#            uplink, "others" to every other one (the lowest metric
#            carries the traffic).
#   uplinks  one attribute set per uplink:
#     kind     "vm": the path through the two service VMs (host-networks.nix);
#              "ethernet": a cable on the host itself. The uplink with a
#              gateway is the path through the VMs, its device the inner
#              end of the host's cable on the workstations' switch (host.nix
#              makes the pair). A cable (an uplink with vendor and product)
#              takes either as its route at the start: "vm", its card handed
#              to the Wi-Fi VM, so the host and every VM go out over it
#              through the firewall VM, every connection logged and ruled;
#              "ethernet", its card the host's alone, nothing logged, the
#              VMs going out over Wi-Fi. gate reroute changes the route
#              while the host runs; the host's profile of the cable keeps it
#              across restarts (the profile connects by itself only while
#              the route is direct), so this value counts only when that
#              profile is made. While the route goes through the firewall
#              VM, gate NAME, gate NAME off and gate prefer act inside the
#              Wi-Fi VM, on the cable and on the Wi-Fi, for the host and
#              every VM together. Inside the Wi-Fi VM the card is named
#              after its entry and -card, as the Wi-Fi card is wifi-card.
#     device   the host's interface the profile uses.
#     pci      the PCI address of the Wi-Fi card the Wi-Fi VM holds and
#     drivers  the kernel drivers that take it; the host never loads them.
#     prefix   the length of the host's address on device (the address is
#              the host's entry in stations.nix) and
#     gateway  the firewall VM's address there, also the host's DNS.
#     vendor   the card's USB vendor id and
#     product  its USB product id; the interface is named device by them on
#              the host, and the Wi-Fi VM's QEMU takes the card by them.
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
