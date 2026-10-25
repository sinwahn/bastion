# /etc/nixos/modules/isolation/net.nix
# The Wi-Fi VM: it alone holds the Wi-Fi card; the host never
# drives it again. A microVM, started with the host. Its
# names come from host-networks.nix; a cable inside it is named after
# where it leads.
#   Wi-Fi  NetworkManager; "gate wifi" opens its Wi-Fi screen (nmtui).
#   cable  toward the firewall VM: 10.199.0.1 on the switch between the
#          two VMs; only the firewall VM (10.199.0.2) may use this VM, for
#          names (DNS) and to go out over the Wi-Fi.
# Its saved Wi-Fi networks live on net-state.img in its state folder.
# wifi-check answers the bastion tool's path check over vsock: the Wi-Fi
# card's state, read only.
{ config, lib, pkgs, local, ... }:

let
  # The Wi-Fi VM's Wi-Fi card: the uplinks of uplinks.nix that name a PCI
  # card, with its address and the drivers that take it on the host.
  cards = lib.filter (u: u ? pci) (lib.attrValues (import ./uplinks.nix).uplinks);

  # The host's key for "gate wifi" (the public half of the key in
  # /root/.ssh named after this VM, made as local.example.nix says).
  hostKey = local.hostKey;

  hostNetworks = import ./host-networks.nix;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  wifiCard = hostNetworks.wifi-card;

  # wifi-check: the Wi-Fi card's state for the bastion tool's path check, read
  # only, as gate status reads it (its state, 100 meaning connected, and the
  # saved network it is connected to): "wifi connected NAME" or "wifi
  # not-connected"; nothing when nmcli cannot read the card.
  checkPort = 52962;
  wifiCheck = pkgs.writeShellScript "wifi-check" ''
    set -u
    if r=$(nmcli -e no -g GENERAL.STATE device show ${wifiCard} 2>/dev/null && nmcli -e no -g GENERAL.CONNECTION device show ${wifiCard} 2>/dev/null); then
      s=$(printf '%s\n' "$r" | sed -n 1p)
      if [ "''${s%% *}" = 100 ]; then
        echo "wifi connected $(printf '%s\n' "$r" | sed -n 2p)"
      else
        echo "wifi not-connected"
      fi
    fi
  '';

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
        iifname "${firewallVm}" ip saddr 10.199.0.2 oifname "${wifiCard}" accept
      }

      chain out {
        type nat hook postrouting priority srcnat;
        oifname "${wifiCard}" masquerade
      }
    }
  '';
in
{
  # The host: never load the Wi-Fi card's driver; the Wi-Fi VM takes the card.
  boot.blacklistedKernelModules = lib.concatMap (u: u.drivers) cards;

  microvm.vms.${wifiVm}.config = {
    system.stateVersion = "26.05";

    microvm = {
      hypervisor = "qemu";
      vcpu = 1;
      mem = 1024;
      devices = map (u: { bus = "pci"; path = u.pci; }) cards;
      interfaces = [
        { type = "tap"; id = hostNetworks.cables.wifi-vm.name; mac = "02:00:00:0a:00:01"; }
      ];
      volumes = [ {
        image = "net-state.img";
        mountPoint = "/var/lib/NetworkManager";
        size = 64;
      }
      {
        image = "ssh-host-keys.img";
        mountPoint = "/var/lib/ssh-host-keys";
        size = 16;
      } ];
      shares = [ {
        proto = "virtiofs";
        tag = "journal";
        socket = "journal.sock";
        source = "${config.microvm.stateDir}/${wifiVm}/journal";
        mountPoint = "/var/log/journal";
      } ];
      vsock.cid = 10;
      vsock.ssh.enable = true;
    };

    # The Wi-Fi card's firmware and the radio rules. The country whose
    # radio rules apply is the machine's own: its folder
    # (hosts/bastion/default.nix) sets it in this VM's configuration.
    hardware.enableRedistributableFirmware = true;
    hardware.wirelessRegulatoryDatabase = true;

    networking.networkmanager.enable = true;
    networking.networkmanager.unmanaged = [ "interface-name:${firewallVm}" ];
    networking.networkmanager.settings.keyfile.path = "/var/lib/NetworkManager/system-connections";
    systemd.tmpfiles.rules = [ "d /var/lib/NetworkManager/system-connections 0700 root root -" ];
    services.resolved.enable = true;
    services.resolved.settings.Resolve.DNSStubListenerExtra = "10.199.0.1";

    systemd.network.enable = true;
    networking.useDHCP = false;
    systemd.network.links."10-${firewallVm}" = {
      matchConfig.MACAddress = "02:00:00:0a:00:01";
      linkConfig.Name = firewallVm;
    };
    systemd.network.networks."10-${firewallVm}" = {
      matchConfig.Name = firewallVm;
      address = [ "10.199.0.1/24" ];
      networkConfig.IPv6AcceptRA = false;
      linkConfig.RequiredForOnline = "no";
    };
    # The Wi-Fi card takes its name from host-networks.nix, found by the
    # drivers of the card in uplinks.nix (the same uplinks as cards above).
    systemd.network.links."10-${wifiCard}" = {
      matchConfig.Driver = lib.concatStringsSep " " (lib.concatMap (u: u.drivers) cards);
      linkConfig.Name = wifiCard;
    };
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    networking.firewall.enable = false;
    networking.nftables.enable = true;
    networking.nftables.ruleset = ruleset;

    # Only the host reaches this VM's login, over vsock (no network), with its key.
    services.openssh.listenAddresses = [ { addr = "127.0.0.1"; port = 22; } ];
    # sshd's host key lives on its own volume; on the tmpfs root a fresh key was made at every boot and gate wifi refused it after each restart
    services.openssh.hostKeys = [ { type = "ed25519"; path = "/var/lib/ssh-host-keys/ssh_host_ed25519_key"; } ];
    users.users.root.openssh.authorizedKeys.keys = [ hostKey ];

    # wifi-check when the host connects to its vsock port: one run per
    # connection, its line back to the host, its errors in the journal.
    systemd.sockets.wifi-check = {
      description = "A run of wifi-check for each connection of the host";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "vsock::${toString checkPort}" ];
      socketConfig.Accept = true;
    };
    systemd.services."wifi-check@" = {
      description = "The Wi-Fi card's state for the bastion tool's path check, read only";
      path = [ pkgs.networkmanager ];
      serviceConfig.ExecStart = "${wifiCheck}";
      serviceConfig.StandardInput = "socket";
      serviceConfig.StandardOutput = "socket";
      serviceConfig.StandardError = "journal";
    };
  };

  # Copy to read: in /etc/bastion, named after this VM.
  environment.etc."bastion/${wifiVm}.nft".text = ruleset;
}
