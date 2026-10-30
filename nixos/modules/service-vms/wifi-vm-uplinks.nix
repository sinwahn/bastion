# uplinks, a command inside the Wi-Fi VM, is gate's way to the allowance and
# the metric of the Wi-Fi and of each cable that VM holds. wifi-check
# answers gate status and the bastion tool's path check over vsock, read
# only, with the Wi-Fi card's state and the facts of uplinks.
{ lib, pkgs, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  wifiVm = hostNetworks.vms.wifi-vm;
  wifiCard = hostNetworks.wifi-card;
  inherit (import ../networks/uplink-roles.nix { inherit lib; }) uplinkList uplinkThroughVms cables;
  inherit (import ./wifi-vm-cards.nix { inherit lib; }) uplinksInside cardNameInside;
  otherMetric = toString uplinkList.metric.others;
  uplinksCommand = pkgs.writeShellScriptBin "uplinks" ''
    set -uf
    PATH=${lib.makeBinPath [ pkgs.networkmanager pkgs.iproute2 pkgs.gawk pkgs.coreutils pkgs.gnused pkgs.gnugrep ]}:$PATH
    nl='
    '
    profiles() {
      case "$1" in
      ${uplinkThroughVms}) nmcli -e no -g NAME,TYPE connection show | sed -n 's/:802-11-wireless$//p' ;;
      ${lib.concatMapStrings (n: "${n}) echo ${n} ;;\n      ") (lib.attrNames cables)}*) echo "STOP: no uplink '$1' in ${wifiVm}: ${toString uplinksInside}." >&2; return 1 ;;
      esac
    }
    card() {
      case "$1" in
      ${lib.concatMapStrings (n: "${n}) echo ${cardNameInside n} ;;\n      ") uplinksInside}esac
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
      for n in ${toString uplinksInside}; do
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
        case "$m" in "" | -*) m=${otherMetric} ;; esac
        echo "uplink $n $u $a $m"
      done
      dev=$(ip -4 route show default | awk '{ m = 0; for (i = 1; i < NF; i++) { if ($i == "dev") d = $(i + 1); if ($i == "metric") m = $(i + 1) } print m, d }' | sort -n | head -n 1 | cut -d' ' -f2)
      case "$dev" in
      ${lib.concatMapStrings (n: "${cardNameInside n}) echo \"route ${n}\" ;;\n      ") uplinksInside}"") echo "route none" ;;
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
  kWifiCheckPort = 52962;
  # 100 is the state of a connected card.
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
in
{
  microvm.vms.${wifiVm}.config = {
    environment.systemPackages = [ uplinksCommand ];
    # One run per connection of the host, its lines back to the host, its
    # errors in the journal.
    systemd.sockets.wifi-check = {
      description = "A run of wifi-check for each connection of the host";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "vsock::${toString kWifiCheckPort}" ];
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
}
