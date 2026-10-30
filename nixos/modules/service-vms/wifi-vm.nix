# The Wi-Fi VM alone holds the Wi-Fi card; the host never drives it again.
# Its saved Wi-Fi networks and the cables' profiles live on net-state.img
# in its state folder.
{ config, lib, local, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  inherit (import ../networks/uplink-roles.nix { inherit lib; }) cables pciCards cableLink;
  inherit (import ./wifi-vm-cards.nix { inherit lib; }) cableCardName uplinksInside cardNameInside;
  serviceVm = import ./service-vm.nix { inherit config lib; };
  ruleSet = import ./service-vm-rule-set.nix;
  outwardCards = lib.concatMapStringsSep ", " (n: "\"${cardNameInside n}\"") uplinksInside;
  ruleset = ''
    table inet ${wifiVm} {
      chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        ct state established,related accept
        iifname "${firewallVm}" ip saddr 10.199.0.2 udp dport 53 accept
        iifname "${firewallVm}" ip saddr 10.199.0.2 tcp dport 53 accept
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        iifname "${firewallVm}" ip saddr 10.199.0.2 oifname { ${outwardCards} } accept
      }

      chain out {
        type nat hook postrouting priority srcnat;
        oifname { ${outwardCards} } masquerade
      }
    }
  '';
in
{
  config = lib.mkMerge [
    (serviceVm {
      name = wifiVm;
      mem = 1024;
      vsockNumber = 10;
      interfaces = [ {
        cable = hostNetworks.cables.wifi-vm.name;
        mac = "02:00:00:0a:00:01";
        leadsTo = firewallVm;
        network = {
          address = [ "10.199.0.1/24" ];
          linkConfig.RequiredForOnline = "no";
        };
      } ];
      volumes = [ {
        image = "net-state.img";
        mountPoint = "/var/lib/NetworkManager";
        size = 64;
      } ];
      login = true;
    })
    (ruleSet wifiVm ruleset)
    {
      boot.blacklistedKernelModules = lib.concatMap (u: u.drivers) pciCards;
      microvm.vms.${wifiVm}.config = {
        # Each cable's card is declared under its entry's name, the id gate
        # reroute hands it and takes it back by.
        microvm.devices = map (u: { bus = "pci"; path = u.pci; }) pciCards
          ++ lib.mapAttrsToList (n: u: { bus = "usb"; path = "vendorid=0x${u.vendor},productid=0x${u.product},id=${n}"; }) cables;
        # The country whose radio rules apply is the machine's own: its
        # folder (hosts/bastion/default.nix) sets it in this VM.
        hardware.enableRedistributableFirmware = true;
        hardware.wirelessRegulatoryDatabase = true;
        networking.networkmanager.enable = true;
        networking.networkmanager.unmanaged = [ "interface-name:${firewallVm}" ];
        networking.networkmanager.settings.keyfile.path = "/var/lib/NetworkManager/system-connections";
        systemd.tmpfiles.rules = [ "d /var/lib/NetworkManager/system-connections 0700 root root -" ];
        services.resolved.enable = true;
        services.resolved.settings.Resolve.DNSStubListenerExtra = "10.199.0.1";
        systemd.network.links = {
          "10-${hostNetworks.wifi-card}" = {
            matchConfig.Driver = lib.concatStringsSep " " (lib.concatMap (u: u.drivers) pciCards);
            linkConfig.Name = hostNetworks.wifi-card;
          };
        } // lib.mapAttrs' (n: u: lib.nameValuePair "10-${cableCardName n}" (cableLink (cableCardName n) u)) cables;
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        users.users.root.openssh.authorizedKeys.keys = [ local.hostKey ];
      };
    }
  ];
}
