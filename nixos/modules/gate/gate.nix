{ config, lib, pkgs, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  switches = hostNetworks.switches;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  liveDataFile = hostNetworks."networks.json";
  inherit (import ../networks/station-roles.nix { inherit lib; }) hostEntry hostIp;
  inherit (import ../networks/uplink-roles.nix { inherit lib; }) uplinkList uplinks uplinkNames uplinkThroughVms cables cableNames hostCableInnerEnd dnsOf;
  inherit (import ../service-vms/service-vm-locations.nix { inherit config lib; }) vsockNumber journalFolder;
  cablesOnSwitch = import ../networks/switch-cables.nix { inherit lib; };
  uplinkFunctions = import ../networks/uplink-functions.nix { inherit config lib pkgs; };
  ensureStep = config.systemd.services.uplinks-ensure.serviceConfig.ExecStart;
  rerouteSentence = k: n: lib.replaceStrings [ "{cable}" "{firewall}" ] [ n firewallVm ] hostNetworks.reroute.${k};
  helpLines = [
    "gate status: ${lib.concatStringsSep ", " (lib.attrValues hostNetworks.vms)}, the switches and their cables, the uplinks and the way out, seen from the host"
  ] ++ lib.concatLists (lib.mapAttrsToList (n: u: [
    ("gate ${n}: " + (if u ? gateway
      then "${wifiVm}'s Wi-Fi screen (nmtui), then allow ${n}: it may carry the host's route and DNS; while a cable is rerouted, the Wi-Fi inside ${wifiVm} may carry the way out of the host and every VM"
      else "allow ${n}: it may carry the host's route and DNS, by itself whenever plugged in; while it is rerouted, inside ${wifiVm}, the way out of the host and every VM"))
    "gate ${n} off: withdraw ${n}: no route or DNS over it, the host's, or while its allowance is inside ${wifiVm} the host's and every VM's; its link stays up"
  ]) uplinks) ++ [
    "gate prefer NAME: NAME (${lib.concatStringsSep ", " uplinkNames}) carries the traffic when more than one is allowed and up"
  ] ++ lib.concatMap (n: [
    "gate reroute ${n} through ${firewallVm}: ${n}'s card to ${wifiVm}: the host and every VM go out over ${n} through ${firewallVm}, every connection logged and ruled"
    "gate reroute ${n} direct to host: ${n}'s card back to the host: only the host goes out over ${n}, nothing logged; the VMs go out over Wi-Fi"
  ]) cableNames ++ [
    "gate log [NAME]: ${firewallVm}'s log of NAME (or of all): names asked, connections made and refused"
  ];

  gate = pkgs.writeShellScriptBin "gate" ''
    ${lib.concatMapStrings (l: "# ${l}\n") helpLines}set -u
    # A command run inside ${wifiVm} over ssh, for gate status. The ssh ends
    # after the seconds of internet-wait (host-networks.nix) when no answer
    # has come; it reads no input (-n), since timeout runs it in a process
    # group of its own, where reading the terminal would stop it.
    ${wifiVm}() {
      sudo ${pkgs.coreutils}/bin/timeout ${toString hostNetworks.internet-wait} \
        ssh -n -i /root/.ssh/${wifiVm} -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=/root/.ssh/known_hosts_${wifiVm} root@vsock/${vsockNumber wifiVm} "$@"
    }
    . ${uplinkFunctions}
    # allow NAME yes DNS | allow NAME no: the allowance, the same for every
    # uplink; the profile and its link stay up either way.
    allow() {
      if [ "$2" = yes ]; then nd=no; d=''${3:-}; else nd=yes; d=; fi
      apply "$1" ipv4.never-default $nd ipv6.never-default $nd ipv4.ignore-auto-dns $nd ipv6.ignore-auto-dns $nd ipv4.dns "$d"
      if [ "$2" = yes ] && ! active "$1"; then
        nm connection up "$1" >/dev/null 2>&1 || echo "$1 is not up now; it comes up by itself when its link is there."
      fi
    }
    # dnsof NAME: the DNS NAME gives the host when it is allowed.
    dnsof() {
      case "$1" in
      ${lib.concatStrings (lib.mapAttrsToList (n: u: "${n}) echo \"${dnsOf u}\" ;; ") uplinks)}esac
    }
    # set_allow NAME yes|no: the allowance where NAME's way out is decided:
    # inside ${wifiVm} for a rerouted cable, and for the Wi-Fi while a cable
    # is rerouted; on the host otherwise.
    set_allow() {
      if inside "$1"; then
        ${wifiVm} uplinks allow "$1" "$2" || echo "STOP: ${wifiVm} did not take $1's allowance; the reason stands above. Do: gate status"
      else
        allow "$1" "$2" "$(dnsof "$1")"
      fi
    }
    # prefer_set NAME: the metric pair by NAME, on the host (the ensure step)
    # and, while a cable is rerouted, inside ${wifiVm}: there NAME takes the
    # preferred metric when its way out is decided there, else the Wi-Fi
    # does.
    prefer_set() {
      ${ensureStep} "$1"
      rr=$(rerouted)
      [ -n "$rr" ] || return 0
      if inside "$1"; then q=$1; else q=${uplinkThroughVms}; fi
      for x in ${uplinkThroughVms} $rr; do
        if [ "$x" = "$q" ]; then m=${toString uplinkList.metric.preferred}; else m=${toString uplinkList.metric.others}; fi
        ${wifiVm} uplinks metric "$x" "$m" || echo "STOP: ${wifiVm} did not take $x's metric; the reason stands above. Do: gate status"
      done
    }
    # line through|direct CABLE: the sentence of the cable's route
    # (host-networks.nix).
    line() {
      case "$1 $2" in
      ${lib.concatMapStrings (n: ''
      "through ${n}") echo ${lib.escapeShellArg (rerouteSentence "through" n)} ;;
      "direct ${n}") echo ${lib.escapeShellArg (rerouteSentence "direct" n)} ;;
      '') cableNames}esac
    }
    # through CABLE: CABLE rerouted through ${firewallVm}: its allowance
    # carried into ${wifiVm}, and the Wi-Fi's when no cable was rerouted
    # before; its card handed to ${wifiVm}; its host profile made not to
    # connect by itself, which keeps the route; the host's path through the
    # VMs allowed; the preference carried. Again on a rerouted cable: its
    # card handed again when ${wifiVm}'s QEMU does not hold it.
    through() {
      if [ "$(route "$1")" = vm ]; then
        hand "$1" || { echo "STOP: ${wifiVm}'s QEMU did not take $1's card; the reason stands above. Do: gate status"; return 1; }
        line through "$1"
        return 0
      fi
      p=$(preferred)
      if allowed "$1"; then a=yes; else a=no; fi
      ${wifiVm} uplinks allow "$1" "$a" || { echo "STOP: ${wifiVm} does not answer; $1 stays direct to the host. Do: gate status"; return 1; }
      if [ -z "$(rerouted)" ]; then
        if allowed ${uplinkThroughVms}; then a=yes; else a=no; fi
        ${wifiVm} uplinks allow ${uplinkThroughVms} "$a" || { echo "STOP: ${wifiVm} does not answer; $1 stays direct to the host. Do: gate status"; return 1; }
      fi
      hand "$1" || { echo "STOP: ${wifiVm}'s QEMU did not take $1's card; $1 stays direct to the host. The reason stands above."; return 1; }
      nm connection modify "$1" connection.autoconnect no
      allow ${uplinkThroughVms} yes "$(dnsof ${uplinkThroughVms})"
      prefer_set "$p"
      line through "$1"
    }
    # direct CABLE: CABLE rerouted direct to the host: its card taken back
    # from ${wifiVm}; its allowance carried back to its host profile, which
    # connects by itself again; when no cable stays rerouted, the Wi-Fi's
    # allowance carried back to the host's path through the VMs, and the
    # Wi-Fi allowed again inside ${wifiVm}, where the VMs go out over it;
    # the preference carried.
    direct() {
      if [ "$(route "$1")" = ethernet ]; then
        take "$1" || { echo "STOP: ${wifiVm}'s QEMU did not give $1's card back; the reason stands above."; return 1; }
        line direct "$1"
        return 0
      fi
      p=$(preferred)
      f=$(insidefacts)
      a=$(printf '%s\n' "$f" | awk -v n="$1" '$1 == "uplink" && $2 == n { print (($4 == "allowed") ? "yes" : "no") }')
      w=$(printf '%s\n' "$f" | awk -v n=${uplinkThroughVms} '$1 == "uplink" && $2 == n { print (($4 == "allowed") ? "yes" : "no") }')
      take "$1" || { echo "STOP: ${wifiVm}'s QEMU did not give $1's card back; $1 stays rerouted through ${firewallVm}. The reason stands above."; return 1; }
      nm connection modify "$1" connection.autoconnect yes
      if [ -z "$a" ]; then
        echo "$1's allowance could not be read from ${wifiVm}: it is withdrawn. Do: gate $1"
        a=no
      fi
      allow "$1" "$a" ""
      if [ -z "$(rerouted)" ]; then
        allow ${uplinkThroughVms} "''${w:-yes}" "$(dnsof ${uplinkThroughVms})"
        ${wifiVm} uplinks allow ${uplinkThroughVms} yes || echo "${wifiVm} did not take the Wi-Fi's allowance back, so the VMs may not go out over Wi-Fi. Do: gate ${uplinkThroughVms}"
      fi
      prefer_set "$p"
      line direct "$1"
    }
    # The device of the host's default route with the lowest metric; empty
    # when the host has no default route.
    routedev() {
      ip -4 route show default | awk '{ m = 0; for (i = 1; i < NF; i++) { if ($i == "dev") d = $(i + 1); if ($i == "metric") m = $(i + 1) } print m, d }' | sort -n | head -n 1 | cut -d' ' -f2
    }
    # uplinks: the facts of each uplink, of each cable's route and of the
    # host's route, one per line in the form status_print names, for gate
    # status and, through status_lines, for gate NAME, gate NAME off, gate
    # prefer and gate reroute. An uplink whose way out is decided inside
    # ${wifiVm} is read from wifi-check there; so is the way out of the
    # host's route through the VMs while a cable is rerouted.
    uplinks() {
      p=$(preferred)
      rr=$(rerouted)
      if [ -n "$rr" ]; then f=$(insidefacts); else f=; fi
      for n in ${toString uplinkNames}; do
        if inside "$n"; then
          l=$(printf '%s\n' "$f" | awk -v n="$n" '$1 == "uplink" && $2 == n { print $3, $4 }')
          case "$l" in
          "") echo "uplink $n unreadable"; continue ;;
          "up "*) u=up ;;
          *) u=not-up ;;
          esac
          case "$l" in *" allowed") a=allowed ;; *) a=not-allowed ;; esac
        else
          if active "$n"; then u=up; else u=not-up; fi
          if allowed "$n"; then a=allowed; else a=not-allowed; fi
        fi
        if [ "$n" = "$p" ]; then echo "uplink $n $u $a preferred"; else echo "uplink $n $u $a other"; fi
      done
      for n in ${toString cableNames}; do echo "reroute $n $(route "$n")"; done
      dev=$(routedev)
      case "$dev" in
      ${hostCableInnerEnd})
        if [ -n "$rr" ]; then
          v=$(printf '%s\n' "$f" | sed -n 's/^route //p' | sed -n 1p)
          case "$v" in
          "") echo "route ${uplinkThroughVms}" ;;
          none) echo "route none" ;;
          "other "*) echo "route other ''${v#other } through" ;;
          *) echo "route $v through" ;;
          esac
        else
          echo "route ${uplinkThroughVms}"
        fi
        ;;
      ${lib.concatStrings (lib.mapAttrsToList (n: u: "${u.device}) echo \"route ${n}\" ;;\n      ") cables)}"") echo "route none" ;;
      *) echo "route other $dev" ;;
      esac
    }
    # gate status. What it means when a service VM is not running
    # (host-networks.nix), and the cables that belong on each switch.
    meaning() {
      case "$1" in
      ${lib.concatStrings (lib.mapAttrsToList (k: v: "${v}) echo ${lib.escapeShellArg hostNetworks.meanings.${k}} ;;\n      ") hostNetworks.vms)}esac
    }
    expected() {
      case "$1" in
      ${lib.concatMapStrings (s: "${s}) echo ${toString (cablesOnSwitch s)} ;;\n      ") (lib.attrValues switches)}esac
    }
    # status_print: the lines of gate status from the facts read from the
    # host, one fact per line on standard input:
    #   vm NAME running | vm NAME stopped
    #   wifi connected PROFILE | wifi not-connected | wifi unreadable
    #   switch NAME up|down CABLE,CABLE,... | switch NAME missing
    #   uplink NAME up|not-up allowed|not-allowed preferred|other
    #   uplink NAME unreadable (its way out is decided inside ${wifiVm},
    #     which does not answer)
    #   reroute CABLE vm|ethernet
    #   route UPLINK | route UPLINK through | route none
    #   route other DEVICE | route other DEVICE through
    #     (through: the host's route goes through ${firewallVm}, and UPLINK
    #     or DEVICE is ${wifiVm}'s way out)
    #   internet yes | internet no
    # The first wrong piece goes on top with what it means and the one thing
    # to do, in this order: a service VM not running; a switch not there or
    # down; a cable not on its switch; ${wifiVm}'s Wi-Fi not connected or
    # not readable, unless a rerouted cable is ${wifiVm}'s way out; no route
    # of the host; no internet. Then status_lines.
    status_print() {
      facts=$(cat)
      w=$(printf '%s\n' "$facts" | sed -n 's/^wifi //p')
      top=$(
        {
          printf '%s\n' "$facts" | while read -r k n s rest; do
            if [ "$k" = vm ] && [ "$s" != running ]; then
              echo "$n is not running: $(meaning "$n"). Do: sudo systemctl start microvm@$n.service"
            fi
          done
          printf '%s\n' "$facts" | while read -r k n s rest; do
            if [ "$k" = switch ]; then
              case "$s" in
              up) ;;
              missing) echo "$n is not there: the host makes its switches when it starts. Do: restart the host" ;;
              *) echo "$n is down: the host makes its switches when it starts. Do: restart the host" ;;
              esac
            fi
          done
          printf '%s\n' "$facts" | while read -r k n s rest; do
            if [ "$k" = switch ] && [ "$s" != missing ]; then
              for c in $(expected "$n"); do
                case ",$rest," in
                *",$c,"*) ;;
                *) echo "$c is not on $n. Do: sudo systemctl restart networks-apply.service" ;;
                esac
              done
            fi
          done
          if ! printf '%s\n' "$facts" | grep -qE '^route (${lib.concatStringsSep "|" cableNames}) through$'; then
            case "$w" in
            "" | connected*) ;;
            not-connected) echo "${wifiVm}'s Wi-Fi is not connected: $(meaning ${wifiVm}). Do: gate ${uplinkThroughVms}" ;;
            *) echo "${wifiVm}'s Wi-Fi cannot be read: $(meaning ${wifiVm}). Do: gate ${uplinkThroughVms}" ;;
            esac
          fi
          if printf '%s\n' "$facts" | grep -qx 'route none'; then
            echo "the host's route: none. Do: ${lib.concatMapStringsSep " or " (n: "gate ${n}") uplinkNames}"
          fi
          if printf '%s\n' "$facts" | grep -qx 'internet no'; then
            echo "internet: no: the host's route reaches no internet. Do: gate prefer the other uplink, or check the network its uplink is on"
          fi
        } | sed -n 1p
      )
      if [ -n "$top" ]; then
        printf 'WRONG: %s\n\n' "$top"
      else
        printf 'Nothing is wrong.\n\n'
      fi
      printf '%s\n' "$facts" | status_lines
    }
    # status_lines: one line per piece, in the order of the facts on
    # standard input. The Wi-Fi VM's line reads w, the Wi-Fi fact, set by
    # status_print; gate NAME, gate NAME off and gate prefer give it the
    # facts of uplinks alone, which have no line of a VM.
    status_lines() {
      while read -r k n s rest; do
        case "$k" in
        vm)
          if [ "$s" != running ]; then
            echo "$n: not running"
          elif [ "$n" = ${wifiVm} ]; then
            case "$w" in
            connected*) echo "$n: running, Wi-Fi connected to ''${w#connected }" ;;
            not-connected) echo "$n: running, Wi-Fi not connected" ;;
            *) echo "$n: running, its Wi-Fi cannot be read" ;;
            esac
          else
            echo "$n: running"
          fi
          ;;
        switch)
          if [ "$s" = missing ]; then
            echo "$n: not there"
          else
            if [ "$s" = up ]; then l="$n: up"; else l="$n: down"; fi
            if [ -n "$rest" ]; then
              l="$l, cables on it: $(printf '%s' "$rest" | sed 's/,/, /g')"
            else
              l="$l, no cables on it"
            fi
            m=
            for c in $(expected "$n"); do
              case ",$rest," in
              *",$c,"*) ;;
              *) m="$m''${m:+, }$c" ;;
              esac
            done
            if [ -n "$m" ]; then l="$l; missing: $m"; fi
            echo "$l"
          fi
          ;;
        uplink)
          if [ "$s" = unreadable ]; then
            echo "$n: cannot be read: ${wifiVm} does not answer"
            continue
          fi
          if [ "$s" = up ]; then l="$n: up"; else l="$n: not up"; fi
          case "$rest" in
          allowed*) l="$l, allowed" ;;
          *) l="$l, not allowed" ;;
          esac
          case "$rest" in
          *" preferred") l="$l, preferred" ;;
          esac
          echo "$l"
          ;;
        reroute)
          if [ "$s" = vm ]; then line through "$n"; else line direct "$n"; fi
          ;;
        route)
          case "$n" in
          none) echo "the host's route: none" ;;
          other)
            if [ "$rest" = through ]; then
              echo "the host's route: through ${firewallVm}, out over $s, not an uplink of uplinks.nix"
            else
              echo "the host's route: $s, not an uplink of uplinks.nix"
            fi
            ;;
          *)
            if [ "$s" = through ]; then echo "the host's route: $n, through ${firewallVm}"; else echo "the host's route: $n"; fi
            ;;
          esac
          ;;
        internet) echo "internet: $n" ;;
        esac
      done
    }
    ${ensureStep}
    case "''${1:-}" in
    status)
      # The facts, read live: each service VM's unit; inside the running
      # Wi-Fi VM, its Wi-Fi card's state and the saved network it is
      # connected to, as wifi-check answers within the seconds of
      # internet-wait, its Wi-Fi unreadable without that answer; each switch
      # of host-networks.nix and the devices on it, from one listing of the
      # host's devices; each uplink; each cable's route; the host's route;
      # the internet.
      {
        for v in ${toString (lib.attrValues hostNetworks.vms)}; do
          if [ "$(systemctl is-active microvm@$v.service)" != active ]; then
            echo "vm $v stopped"
            continue
          fi
          echo "vm $v running"
          if [ "$v" = ${wifiVm} ]; then
            wl=$(insidefacts | grep '^wifi ' | sed -n 1p)
            echo "''${wl:-wifi unreadable}"
          fi
        done
        links=$(ip -j link show) || links='[]'
        for s in ${toString (lib.attrValues switches)}; do
          printf '%s' "$links" | ${pkgs.jq}/bin/jq -r --arg s "$s" '
            [.[] | select(.ifname == $s)][0] as $sw
            | if $sw == null then "switch \($s) missing"
              else "switch \($s) \(if ($sw | .operstate) == "UP" then "up" else "down" end) \([.[] | select(.master == $s) | .ifname] | join(","))"
              end'
        done
        uplinks
        if curl -s -m ${toString hostNetworks.internet-wait} -o /dev/null ${lib.escapeShellArg hostNetworks.internet}; then
          echo "internet yes"
        else
          echo "internet no"
        fi
      } | status_print
      ;;
    ${lib.concatStrings (lib.mapAttrsToList (n: u: ''
    ${n})
      if [ "''${2:-}" = off ]; then
        set_allow ${n} no
      else
        ${lib.optionalString (u ? gateway) ''
        sudo ssh -i /root/.ssh/${wifiVm} -o StrictHostKeyChecking=accept-new \
          -o UserKnownHostsFile=/root/.ssh/known_hosts_${wifiVm} -t root@vsock/${vsockNumber wifiVm} nmtui
        ''}set_allow ${n} yes
      fi
      uplinks | status_lines
      ;;
    '') uplinks)}prefer)
      case "''${2:-}" in
      ${lib.concatMapStrings (n: "${n}) prefer_set ${n} ;; ") uplinkNames}*) echo "STOP: name an uplink of modules/isolation/uplinks.nix: ${toString uplinkNames}."; exit 1 ;;
      esac
      uplinks | status_lines
      ;;
    reroute)
      # The words after reroute, the fifth empty for "through".
      case "''${2:-} ''${3:-} ''${4:-} ''${5:-}" in
      ${lib.concatMapStrings (n: ''
      "${n} through ${firewallVm} ") through ${n} || exit 1 ;;
      "${n} direct to host") direct ${n} || exit 1 ;;
      '') cableNames}*) echo ${lib.escapeShellArg "STOP: name a cable of modules/isolation/uplinks.nix (${toString cableNames}) and its route: gate reroute CABLE through ${firewallVm}, or gate reroute CABLE direct to host."}; exit 1 ;;
      esac
      echo
      uplinks | status_lines
      ;;
    log)
      # NAME's ip: the host's from stations.nix; any other station's from
      # the live data file, read now, so a VM the bastion tool made is found.
      ip=
      if [ "''${2:-}" = ${hostEntry} ]; then
        ip=${hostIp}
      elif [ -n "''${2:-}" ]; then
        ip=$(${pkgs.jq}/bin/jq -r --arg n "$2" '.stations[$n].ip // empty' ${liveDataFile} 2>/dev/null) || ip=
        [ -n "$ip" ] || { echo "STOP: no station '$2' could be read from ${liveDataFile}."; exit 1; }
      fi
      if [ -n "$ip" ]; then
        sudo journalctl -D ${journalFolder firewallVm} --no-pager -n 300 -g "(gate|query|reply|forwarded|DHCP).*$ip([^0-9]|$)"
      else
        sudo journalctl -D ${journalFolder firewallVm} --no-pager -n 300
      fi
      ;;
    *)
      sed -n '2,${toString (lib.length helpLines + 1)}s/^# //p' "$0"
      ;;
    esac
  '';
in
{
  # gate status runs curl.
  environment.systemPackages = [ gate pkgs.curl ];
}
