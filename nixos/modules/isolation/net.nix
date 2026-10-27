# /etc/nixos/modules/isolation/net.nix
# The Wi-Fi VM: it alone holds the Wi-Fi card; the host never
# drives it again. A microVM, started with the host. Its
# names come from host-networks.nix; a cable inside it is named after
# where it leads.
#   Wi-Fi  NetworkManager; "gate wifi" opens its Wi-Fi screen (nmtui).
#   cable  toward the firewall VM: 10.199.0.1 on the switch between the
#          two VMs; only the firewall VM (10.199.0.2) may use this VM, for
#          names (DNS) and to go out over the Wi-Fi.
#   cards  each cable of uplinks.nix (an uplink with vendor and product) is
#          declared to this VM's QEMU by its USB ids, under its entry's
#          name; while its route goes through the firewall VM (gate
#          reroute, host.nix) this VM holds its card, named after its entry
#          and -card, and the firewall VM may go out over it too; its
#          profile, named after its entry, carries nothing until gate
#          allows it.
# Its saved Wi-Fi networks and the cables' profiles live on net-state.img
# in its state folder.
# wifi-check answers the bastion tool's path check and gate status over
# vsock: the Wi-Fi card's state and the facts of uplinks, read only.
# uplinks, a command inside this VM, is gate's way to the allowance and the
# metrics of the Wi-Fi and of the cables this VM holds.
{ config, lib, pkgs, local, ... }:

let
  ul = import ./uplinks.nix;

  # The Wi-Fi VM's Wi-Fi card: the uplinks of uplinks.nix that name a PCI
  # card, with its address and the drivers that take it on the host.
  cards = lib.filter (u: u ? pci) (lib.attrValues ul.uplinks);

  # The uplink through the VMs (the one with the firewall VM's address as
  # its gateway): inside this VM its allowance and metric are the Wi-Fi's.
  pathUplink = lib.head (lib.attrNames (lib.filterAttrs (n: u: u ? gateway) ul.uplinks));
  # The cables of uplinks.nix, by their entries; inside this VM a cable's
  # card is named after its entry and -card.
  cables = lib.filterAttrs (n: u: u ? vendor) ul.uplinks;
  cardOf = n: "${n}-card";
  # The uplinks whose way out this VM may carry, and the card of each.
  inside = [ pathUplink ] ++ lib.attrNames cables;
  cardIn = n: if n == pathUplink then wifiCard else cardOf n;
  outward = lib.concatMapStringsSep ", " (n: "\"${cardIn n}\"") inside;
  # The longest network device name the kernel takes: IFNAMSIZ (16) less
  # its end byte.
  nameMax = 15;
  others = toString ul.metric.others;

  # The host's key for "gate wifi" (the public half of the key in
  # /root/.ssh named after this VM, made as local.example.nix says).
  hostKey = local.hostKey;

  hostNetworks = import ./host-networks.nix;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  wifiCard = hostNetworks.wifi-card;

  # uplinks: gate's way to the allowance and the metric of each uplink this
  # VM may carry the way out over, and their facts for wifi-check. The
  # Wi-Fi's profiles are every saved Wi-Fi network; a cable's is the one
  # named after its entry. An active profile takes a change at once.
  #   uplinks facts: one line per uplink, "uplink NAME up|not-up
  #     allowed|not-allowed METRIC", then "route NAME", "route none" or
  #     "route other DEVICE" by this VM's default route of the lowest
  #     metric.
  #   uplinks allow NAME yes|no: NAME may carry this VM's default route and
  #     DNS, or not; its link stays up either way.
  #   uplinks metric NAME METRIC: NAME's route metric.
  uplinksCommand = pkgs.writeShellScriptBin "uplinks" ''
    set -uf
    PATH=${lib.makeBinPath [ pkgs.networkmanager pkgs.iproute2 pkgs.gawk pkgs.coreutils pkgs.gnused pkgs.gnugrep ]}:$PATH
    nl='
    '
    profiles() {
      case "$1" in
      ${pathUplink}) nmcli -e no -g NAME,TYPE connection show | sed -n 's/:802-11-wireless$//p' ;;
      ${lib.concatMapStrings (n: "${n}) echo ${n} ;;\n      ") (lib.attrNames cables)}*) echo "STOP: no uplink '$1' in ${wifiVm}: ${toString inside}." >&2; return 1 ;;
      esac
    }
    card() {
      case "$1" in
      ${lib.concatMapStrings (n: "${n}) echo ${cardIn n} ;;\n      ") inside}esac
    }
    # apply NAME FIELD VALUE ...: the fields into each profile of NAME.
    apply() {
      ps=$(profiles "$1") || return 1
      c=$(card "$1")
      shift
      old=$IFS
      IFS=$nl
      for p in $ps; do
        IFS=$old
        nmcli connection modify "$p" "$@" || return 1
        if nmcli -e no -g NAME connection show --active | grep -qxF "$p"; then
          nmcli device reapply "$c" >/dev/null || nmcli connection up "$p" >/dev/null
        fi
      done
      IFS=$old
    }
    facts() {
      for n in ${toString inside}; do
        ps=$(profiles "$n") || continue
        u=not-up
        if [ "$(nmcli -e no -g GENERAL.STATE device show "$(card "$n")" 2>/dev/null | cut -d' ' -f1)" = 100 ]; then u=up; fi
        a=allowed
        m=
        old=$IFS
        IFS=$nl
        for p in $ps; do
          IFS=$old
          [ "$(nmcli -e no -g ipv4.never-default connection show "$p")" = no ] || a=not-allowed
          [ -n "$m" ] || m=$(nmcli -e no -g ipv4.route-metric connection show "$p")
        done
        IFS=$old
        case "$m" in "" | -*) m=${others} ;; esac
        echo "uplink $n $u $a $m"
      done
      dev=$(ip -4 route show default | awk '{ m = 0; for (i = 1; i < NF; i++) { if ($i == "dev") d = $(i + 1); if ($i == "metric") m = $(i + 1) } print m, d }' | sort -n | head -n 1 | cut -d' ' -f2)
      case "$dev" in
      ${lib.concatMapStrings (n: "${cardIn n}) echo \"route ${n}\" ;;\n      ") inside}"") echo "route none" ;;
      *) echo "route other $dev" ;;
      esac
    }
    case "''${1:-}" in
    facts) facts ;;
    allow)
      case "''${3:-}" in
      yes) nd=no ;;
      no) nd=yes ;;
      *) echo "STOP: uplinks allow NAME yes|no" >&2; exit 1 ;;
      esac
      apply "''${2:-}" ipv4.never-default $nd ipv6.never-default $nd ipv4.ignore-auto-dns $nd ipv6.ignore-auto-dns $nd
      ;;
    metric) apply "''${2:-}" ipv4.route-metric "''${3:-}" ipv6.route-metric "''${3:-}" ;;
    *) echo "uplinks facts | uplinks allow NAME yes|no | uplinks metric NAME METRIC" >&2; exit 1 ;;
    esac
  '';

  # uplinks-ensure, inside this VM: each cable's profile, named after its
  # entry, on its card, made when missing, carrying nothing until gate
  # allows it; what gate set in it stays.
  ensureInside = pkgs.writeShellScript "uplinks-ensure" ''
    set -u
    ${lib.concatMapStrings (n: ''
    nmcli connection show ${n} >/dev/null 2>&1 \
      || nmcli connection add type ethernet con-name ${n} connection.interface-name ${cardOf n} connection.autoconnect yes ipv4.method auto ipv4.never-default yes ipv6.never-default yes ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes ipv4.route-metric ${others} ipv6.route-metric ${others} >/dev/null
    '') (lib.attrNames cables)}'';

  # wifi-check: the Wi-Fi card's state, read only, as gate status reads it
  # (its state, 100 meaning connected, and the saved network it is
  # connected to): "wifi connected NAME" or "wifi not-connected"; nothing
  # when nmcli cannot read the card. Then the facts of uplinks.
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
    ${uplinksCommand}/bin/uplinks facts
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
        iifname "${firewallVm}" ip saddr 10.199.0.2 oifname { ${outward} } accept
      }

      chain out {
        type nat hook postrouting priority srcnat;
        oifname { ${outward} } masquerade
      }
    }
  '';
in
{
  # The host: never load the Wi-Fi card's driver; the Wi-Fi VM takes the card.
  boot.blacklistedKernelModules = lib.concatMap (u: u.drivers) cards;

  # A cable's card inside this VM is a network device: its name fits one.
  assertions = map (n: {
    assertion = lib.stringLength (cardOf n) <= nameMax;
    message = "modules/isolation/uplinks.nix: inside ${wifiVm} the cable ${n}'s card is named ${cardOf n}, ${toString (lib.stringLength (cardOf n))} characters; a network device's name is at most ${toString nameMax} characters.";
  }) (lib.attrNames cables);

  microvm.vms.${wifiVm}.config = {
    system.stateVersion = "26.05";

    microvm = {
      hypervisor = "qemu";
      vcpu = 1;
      mem = 1024;
      # The Wi-Fi card, and each cable's card by its USB ids under its
      # entry's name, the id gate reroute hands it and takes it back by.
      devices = map (u: { bus = "pci"; path = u.pci; }) cards
        ++ lib.mapAttrsToList (n: u: { bus = "usb"; path = "vendorid=0x${u.vendor},productid=0x${u.product},id=${n}"; }) cables;
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
    # No automatic connection on a cable's card: only its profile runs on it.
    networking.networkmanager.settings.main.no-auto-default =
      lib.concatMapStringsSep ";" (n: "interface-name:${cardOf n}") (lib.attrNames cables);
    systemd.tmpfiles.rules = [ "d /var/lib/NetworkManager/system-connections 0700 root root -" ];
    services.resolved.enable = true;
    services.resolved.settings.Resolve.DNSStubListenerExtra = "10.199.0.1";

    systemd.network.enable = true;
    networking.useDHCP = false;
    # The Wi-Fi card takes its name from host-networks.nix, found by the
    # drivers of the card in uplinks.nix (the same uplinks as cards above);
    # a cable's card takes its name by its USB ids.
    systemd.network.links = {
      "10-${firewallVm}" = {
        matchConfig.MACAddress = "02:00:00:0a:00:01";
        linkConfig.Name = firewallVm;
      };
      "10-${wifiCard}" = {
        matchConfig.Driver = lib.concatStringsSep " " (lib.concatMap (u: u.drivers) cards);
        linkConfig.Name = wifiCard;
      };
    } // lib.mapAttrs' (n: u: lib.nameValuePair "10-${cardOf n}" {
      matchConfig.Property = "ID_VENDOR_ID=${u.vendor} ID_MODEL_ID=${u.product}";
      linkConfig.Name = cardOf n;
    }) cables;
    systemd.network.networks."10-${firewallVm}" = {
      matchConfig.Name = firewallVm;
      address = [ "10.199.0.1/24" ];
      networkConfig.IPv6AcceptRA = false;
      linkConfig.RequiredForOnline = "no";
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

    environment.systemPackages = [ uplinksCommand ];

    # The cables' profiles, made at every start once NetworkManager is up.
    systemd.services.uplinks-ensure = {
      description = "The profiles of the cables of uplinks.nix this VM may hold";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" ];
      path = [ pkgs.networkmanager ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = "${ensureInside}";
    };

    # wifi-check when the host connects to its vsock port: one run per
    # connection, its lines back to the host, its errors in the journal.
    systemd.sockets.wifi-check = {
      description = "A run of wifi-check for each connection of the host";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "vsock::${toString checkPort}" ];
      socketConfig.Accept = true;
    };
    systemd.services."wifi-check@" = {
      description = "The Wi-Fi card's state and the facts of uplinks, for the bastion tool and gate status, read only";
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
