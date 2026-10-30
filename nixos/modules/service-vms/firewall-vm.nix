# The firewall VM is every workstation's and the host's only way out; each
# network of the live data file other than the workstations' is a VLAN on
# its cable toward the workstations, made by firewall-apply
# (firewall-rules.nix).
{ config, lib, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  firewallVm = hostNetworks.vms.firewall-vm;
  workstations = hostNetworks.switches.workstations;
  serviceVm = import ./service-vm.nix { inherit config lib; };
  # The Wi-Fi VM on the switch between the two VMs: this VM's route out,
  # dnsmasq's server and this VM's own nameserver.
  kWifiVmIp = "10.199.0.1";
in
{
  config = lib.mkMerge [
    (serviceVm {
      name = firewallVm;
      mem = 512;
      vsockNumber = 11;
      interfaces = [ {
        cable = hostNetworks.cables.firewall-wifi.name;
        mac = "02:00:00:0a:00:02";
        leadsTo = hostNetworks.vms.wifi-vm;
        network = {
          address = [ "10.199.0.2/24" ];
          routes = [ { Gateway = kWifiVmIp; } ];
          linkConfig.RequiredForOnline = "routable";
        };
      } {
        cable = hostNetworks.cables.firewall-vm.name;
        mac = "02:00:00:0a:00:03";
        leadsTo = workstations;
        network.address = [ "10.200.0.1/24" ];
      } ];
      sharesLiveDataFolder = true;
    })
    {
      microvm.vms.${firewallVm}.config = {
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
        # No router or DNS server option: dnsmasq hands each leg's own
        # address as both.
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = {
            interface = workstations;
            bind-dynamic = true;
            no-resolv = true;
            server = [ kWifiVmIp ];
            domain-needed = true;
            bogus-priv = true;
            dhcp-authoritative = true;
            log-queries = "extra";
            log-dhcp = true;
          };
        };
        # firewall-check's lookups go where the workstations' lookups go;
        # systemd-resolved, on with systemd-networkd, takes the nameservers
        # as its DNS.
        networking.nameservers = [ kWifiVmIp ];
      };
    }
  ];
}
