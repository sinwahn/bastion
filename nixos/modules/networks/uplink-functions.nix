# Not a module: the shell functions of the host's uplink profiles, written
# once for the ensure step (uplink-profiles.nix), uplinks-reroute
# (cable-reroute.nix) and gate (gate.nix), which import this file.
{ config, lib, pkgs }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  inherit (import ./uplink-roles.nix { inherit lib; }) uplinkList uplinkNames uplinkThroughVms cables cableNames;
  inherit (import ../service-vms/service-vm-locations.nix { inherit config lib; }) vsockNumber controlSocket;
  wifiVmControlSocket = controlSocket wifiVm;
  wifiCheckPort = lib.last (lib.splitString ":" (lib.head
    config.microvm.vms.${wifiVm}.config.config.systemd.sockets.wifi-check.listenStreams));
  kProfileFields = "connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.route-metric,ipv6.route-metric,ipv4.never-default,ipv6.never-default,ipv4.ignore-auto-dns,ipv6.ignore-auto-dns";
in
pkgs.writeText "uplinks.sh" ''
  nm() {
    if [ "$(id -u)" = 0 ]; then ${config.networking.networkmanager.package}/bin/nmcli "$@"
    else sudo ${config.networking.networkmanager.package}/bin/nmcli "$@"; fi
  }
  allowed() { [ "$(nm -g ipv4.never-default connection show "$1" 2>/dev/null)" = no ]; }
  active() { nm -g NAME connection show --active | grep -qxF "$1"; }
  asroot() {
    if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
  }
  # route NAME: a cable's route now: "vm", through ${firewallVm}, its card
  # ${wifiVm}'s; "ethernet", direct to the host. Its profile connects by
  # itself only while the route is direct; the list's kind while the
  # profile is not made.
  route() {
    case "$(nm -g connection.autoconnect connection show "$1" 2>/dev/null)" in
    yes) echo ethernet ;;
    no) echo vm ;;
    *)
      case "$1" in
      ${lib.concatStrings (lib.mapAttrsToList (n: u: "${n}) echo ${u.kind} ;; ") cables)}esac
      ;;
    esac
  }
  # rerouted: the cables whose route goes through ${firewallVm}, on one line.
  rerouted() {
    rs=
    for c in ${toString cableNames}; do
      if [ "$(route "$c")" = vm ]; then rs="$rs $c"; fi
    done
    echo $rs
  }
  # inside NAME: NAME's allowance and metric are decided inside ${wifiVm}:
  # a rerouted cable's, and the Wi-Fi's while a cable is rerouted.
  inside() {
    case "$1" in
    ${uplinkThroughVms}) [ -n "$(rerouted)" ] ;;
    *) [ "$(route "$1")" = vm ] ;;
    esac
  }
  # insidefacts: wifi-check's lines (net.nix), the Wi-Fi card's state and
  # the facts of the uplinks inside ${wifiVm}; nothing when it does not
  # answer within the seconds of internet-wait.
  insidefacts() {
    ${pkgs.socat}/bin/socat -t ${toString hostNetworks.internet-wait} - VSOCK-CONNECT:${vsockNumber wifiVm}:${wifiCheckPort} </dev/null 2>/dev/null
  }
  # qmp COMMAND: one command of QEMU's human monitor to ${wifiVm}'s QEMU
  # over its control socket, sent as microvm.nix sends its own; fails,
  # printing why, when the socket does not answer or the command printed
  # anything (its error).
  qmp() {
    qr=$(printf '%s\n' '{"execute":"qmp_capabilities"}' "{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"$1\"}}" \
      | asroot ${pkgs.socat}/bin/socat -t 2 STDIO UNIX:${wifiVmControlSocket},shut-none 2>&1) || { printf '%s\n' "$qr"; return 1; }
    if printf '%s\n' "$qr" | grep -q '"return": ""'; then return 0; fi
    printf '%s\n' "$qr" | ${pkgs.gnused}/bin/sed -n 's/.*"return": "\(.*\)"}.*/\1/p'
    return 1
  }
  # held NAME: ${wifiVm}'s QEMU holds the device of the id NAME.
  held() {
    printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"qom-list","arguments":{"path":"/machine/peripheral"}}' \
      | asroot ${pkgs.socat}/bin/socat -t 2 STDIO UNIX:${wifiVmControlSocket},shut-none 2>/dev/null \
      | grep -q "\"name\": \"$1\""
  }
  # hand NAME: the cable NAME's card to ${wifiVm}'s QEMU, by its USB ids,
  # under the id NAME (net.nix declares it so); take NAME: back from it,
  # the host's driver taking the card again. Each does nothing when it is
  # so already; take does nothing while ${wifiVm} is stopped.
  hand() {
    held "$1" && return 0
    case "$1" in
    ${lib.concatStrings (lib.mapAttrsToList (n: u: "${n}) qmp \"device_add usb-host,vendorid=0x${u.vendor},productid=0x${u.product},id=${n}\" ;; ") cables)}esac
  }
  take() {
    held "$1" || return 0
    qmp "device_del $1"
  }
  # The uplink preferred now: the host's profile with the lowest route
  # metric, a rerouted cable's left out; while a cable is rerouted and
  # that profile is the path through the VMs, the uplink inside ${wifiVm}
  # with the lowest metric; the list's starting value while no profile
  # exists.
  preferred() {
    p=${uplinkList.prefer}; low=
    rp=" $(rerouted) "
    for n in ${toString uplinkNames}; do
      case "$rp" in *" $n "*) continue ;; esac
      m=$(nm -g ipv4.route-metric connection show "$n" 2>/dev/null) || continue
      if [ -z "$low" ] || [ "$m" -lt "$low" ]; then low=$m; p=$n; fi
    done
    if [ "$rp" != "  " ] && [ "$p" = ${uplinkThroughVms} ]; then
      v=$(insidefacts | ${pkgs.gawk}/bin/awk '$1 == "uplink" && (low == "" || $5 + 0 < low + 0) { low = $5; q = $2 } END { print q }')
      if [ -n "$v" ]; then p=$v; fi
    fi
    echo "$p"
  }
  # apply NAME FIELD VALUE ...: the fields into the profile; an active
  # profile takes a change at once.
  apply() {
    n=$1; shift
    before=$(nm -g ${kProfileFields} connection show "$n")
    nm connection modify "$n" "$@" || return 1
    if [ "$(nm -g ${kProfileFields} connection show "$n")" != "$before" ] && active "$n"; then
      nm device reapply "$(nm -g connection.interface-name connection show "$n")" >/dev/null \
        || nm connection up "$n" >/dev/null
    fi
  }
''
