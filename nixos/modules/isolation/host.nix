# /etc/nixos/modules/isolation/host.nix
# The host's part of the isolation layer; the
# switches, the service VMs and their cables are named in host-networks.nix:
# - two switches (bridges) without a network of their own: one between the
#   Wi-Fi VM and the firewall VM, one for the firewall VM, the workstations
#   and the host;
# - the host's uplinks of uplinks.nix: the path through the firewall VM
#   (the host as a station behind it, 10.200.0.2, like every workstation)
#   and the cable on the host, NetworkManager profiles made from the list;
# - the host's cable on the workstations' switch, a veth pair: its port end
#   on the switch, named after the host's entry in stations.nix, and its
#   inner end, the device of the uplink wifi, carrying the host's address;
# - on the workstations' switch each workstation may send only from its own
#   MAC and IP address, and its port, named with its name, is isolated
#   unless its network's reach-each-other in the live data file is true, so
#   workstations reach the firewall VM, and each other only on a network
#   whose reach-each-other is true; the guard keeps
#   them off the host; the guard is built from the live data file
#   (host-networks.nix), which networks-apply writes from the stations of
#   stations.nix that have a MAC when it is missing, and never overwrites;
# - the service VMs' cables put on their switches by networks-apply, again
#   whenever a switch or a cable is made again, and the guard loaded;
# - every network of the live data file a VLAN on the workstations' switch:
#   networks-apply turns its VLAN filtering on and gives the firewall VM's
#   cable there every network's lane, tagged, beside lane 1 untagged (the
#   network of the workstations' switch); the host's port stays on lane 1;
#   a VM's cable carries its network's lane from its libvirt definition
#   (the bastion tool's);
# - a station's or a service cable's name longer than a network device name
#   may be is refused;
# - memory merging (KSM) stays off;
# - the command "gate".
{ config, lib, pkgs, ... }:

let
  st = import ./stations.nix;
  ws = lib.filterAttrs (n: s: s ? mac) st;
  # The longest network device name the kernel takes: IFNAMSIZ (16) less
  # its end byte. Every station's name is its cable's name.
  nameMax = 15;
  hostNetworks = import ./host-networks.nix;
  switches = hostNetworks.switches;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  vmId = name: lib.replaceStrings [ "-" ] [ "" ] config.microvm.vms.${name}.config.config.microvm.machineId;
  # A service VM's vsock number, from its own module.
  vmCid = name: toString config.microvm.vms.${name}.config.config.microvm.vsock.cid;
  # The units networks-apply is part of: each switch's unit, and each
  # service VM's unit that makes its cables (microvm.nix).
  switchUnits = map (s: "${s}-netdev.service") (lib.attrValues switches);
  tapUnits = map (v: "microvm-tap-interfaces@${v}.service") (lib.attrValues hostNetworks.vms);
  # The host: the one station of stations.nix without a MAC. A cable takes
  # the name of the machine it belongs to, so the port end of the host's
  # cable on the workstations' switch is named after its entry; its ip is
  # the host's address,
  # on the inner end.
  hostPort = lib.head (lib.attrNames (lib.filterAttrs (n: s: !(s ? mac)) st));
  hostIp = st.${hostPort}.ip;

  # The live data file (host-networks.nix). When it is missing networks-apply
  # writes it: the network of the workstations' switch on lane 1 (untagged),
  # its ip-range from the gateway and prefix of the uplink through the VMs
  # (uplinks.nix), its VMs not reaching each other, and every station of
  # stations.nix that has a MAC on it.
  networksFile = hostNetworks."networks.json";
  # The lane of the network of the workstations' switch: the switch's default
  # (untagged) lane, the one a cable is on when it joins the switch, which
  # libvirt also counts on (src/util/virnetdevbridge.c 323-324).
  workstationsLane = 1;
  firstWrite = builtins.toJSON {
    network = switches.workstations;
    lane = workstationsLane;
    inherit (lib.head (lib.attrValues vms)) gateway prefix;
    stations = ws;
  };
  # The guard: a bridge table, loaded by networks-apply from the file.
  guardTable = "ws-guard";
  # The cables that belong on switch s: the service cables of
  # host-networks.nix put on it and, on the workstations' switch, the port
  # end of the host's cable. gate status names the ones missing.
  onSwitch = s: lib.optional (s == switches.workstations) hostPort ++ map (c: c.name)
    (lib.filter (c: switches.${c.switch} == s) (lib.attrValues hostNetworks.cables));
  # The ports of the workstations' switch the closed guard lets through:
  # the host's and the service cables on that switch.
  guardPorts = onSwitch switches.workstations;

  # networks-apply's part for the live data file. The file is written when it
  # is missing and never overwritten. The guard is built from it per station:
  # its cable sends only from its MAC and IP address, and no workstation
  # reaches the host (not on the switch, and not through the port end of the
  # host's cable, which is not isolated). It is loaded in one nft run, which
  # the kernel applies whole or not at all. A file it cannot read leaves the
  # guard loaded before; with no guard loaded before, the closed guard drops
  # every frame entering the switch from any port but the host's and the
  # service cables'; the journal says why.
  # The networks as VLANs: the switch's VLAN filtering is turned on first,
  # whatever the file holds; once the guard is loaded from the file, the
  # firewall VM's cable on the switch gets lane 1 untagged and every lane of
  # the file above it tagged (a lane it has already stays as it is). The
  # host's port is given no lane: it keeps lane 1, which it got when it
  # joined the switch. Then every station's cable on the switch is made
  # isolated when its network's reach-each-other is false and not isolated
  # when it is true; the host's port and the firewall VM's cable are no
  # station's and keep their flags.
  networksApplyFile = ''
    file=${networksFile}
    table=${guardTable}
    hostport=${hostPort}
    switch=${switches.workstations}
    cable=${hostNetworks.cables.firewall-vm.name}
    untagged=${toString workstationsLane}
    ports=${lib.escapeShellArg (lib.concatMapStringsSep ", " (n: "\"${n}\"") guardPorts)}
    first=${lib.escapeShellArg firstWrite}
    rc=0
    if ! ip link set dev "$switch" type bridge vlan_filtering 1; then
      echo "$switch keeps its networks apart only with VLAN filtering, which could not be turned on: the reason stands above."
      rc=1
    fi
    if [ ! -e "$file" ]; then
      # Its folder root's and 0755: microvm.nix's tmpfiles rule makes a
      # missing share folder its own and 0775 before this runs.
      dir=$(dirname "$file")
      mkdir -p "$dir"
      chown root:root "$dir"
      chmod 0755 "$dir"
      tmp=$(mktemp "$file.XXXXXX")
      if printf '%s' "$first" | jq '
          .prefix as $p
          | (.gateway | split(".") | map(tonumber)) as $o
          | ([range(4) as $i
              | ([[$p - 8 * $i, 8] | min, 0] | max) as $b
              | $o[$i] - ($o[$i] % pow(2; 8 - $b))]
            | map(tostring) | join(".")) as $net
          | .network as $n
          | {networks: {($n): {lane: .lane, "ip-range": ($net + "/" + ($p | tostring)), "reach-each-other": false}},
             stations: (.stations | map_values({network: $n} + .))}' > "$tmp"; then
        chmod 0644 "$tmp"
        mv "$tmp" "$file"
        echo "$file was missing: written from stations.nix."
      else
        rm -f "$tmp"
        echo "$file was missing and could not be written."
      fi
    fi
    if json=$(cat "$file") && guard=$(printf '%s' "$json" | jq -r --arg table "$table" --arg hostport "$hostport" '
        if (.networks | type) != "object" then error("networks is not a set of networks")
        elif (.stations | type) != "object" then error("stations is not a set of stations")
        else . end
        | .networks as $nets
        | ($nets | to_entries[] | .key as $n | .value
          | if (.lane | type) != "number" or .lane != (.lane | trunc) or .lane < 1 or .lane > 4094
            then error("network \($n): lane \(.lane) is not a whole number from 1 to 4094")
            elif (."reach-each-other" | type) != "boolean" then error("network \($n): reach-each-other is not true or false")
            else empty end),
          .
        | .stations | to_entries
        | map(.key as $n | .value
          | if (.network | type) != "string" or $nets[.network] == null then error("station \($n): its network is not in networks")
            elif (.mac | type) != "string" then error("station \($n): no mac")
            elif (.mac | test("^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$") | not) then error("station \($n): mac \(.mac) is not a MAC")
            elif (.ip | type) != "string" then error("station \($n): no ip")
            elif (.ip | test("^[0-9]{1,3}([.][0-9]{1,3}){3}$") | not) then error("station \($n): ip \(.ip) is not an IPv4 address")
            else {name: $n, mac, ip} end)
        | (map("\"" + .name + "\"") | join(", ")) as $set
        | "table bridge \($table)",
          "delete table bridge \($table)",
          "table bridge \($table) {",
          "  chain pre {",
          "    type filter hook prerouting priority -200; policy accept;",
          (.[] | "    iifname \"\(.name)\" ether saddr != \(.mac) log prefix \"guard \(.name) \" drop",
                 "    iifname \"\(.name)\" ether type arp arp saddr ip != \(.ip) log prefix \"guard \(.name) \" drop",
                 "    iifname \"\(.name)\" ether type ip ip saddr != { 0.0.0.0, \(.ip) } log prefix \"guard \(.name) \" drop",
                 "    iifname \"\(.name)\" ether type != { ip, arp } drop"),
          "  }",
          "  chain in {",
          "    type filter hook input priority -200; policy accept;",
          (if $set == "" then empty else "    iifname { \($set) } ether type ip log prefix \"guard to-host \" drop" end),
          "  }",
          "  chain forward {",
          "    type filter hook forward priority -200; policy accept;",
          (if $set == "" then empty else "    iifname { \($set) } oifname \"\($hostport)\" ether type ip log prefix \"guard to-host \" drop" end),
          "  }",
          "}"') && printf '%s\n' "$guard" | nft -f -; then
      echo "the guard of $switch is loaded from $file."
    else
      echo "the guard of $switch was not loaded from $file; the reason stands above."
      if nft list table bridge "$table" >/dev/null 2>&1; then
        echo "the guard loaded before stays."
      else
        printf '%s\n' "table bridge $table {" "  chain pre {" \
          "    type filter hook prerouting priority -200; policy accept;" \
          "    meta ibrname \"$switch\" iifname != { $ports } drop" "  }" "}" | nft -f -
        echo "no guard was loaded before: the closed guard drops every frame entering $switch from any port but $ports."
      fi
      exit 1
    fi
    if [ -e /sys/class/net/"$cable" ]; then
      ok=yes
      bridge vlan add dev "$cable" vid "$untagged" pvid untagged || ok=no
      for lane in $(printf '%s' "$json" | jq -r --argjson untagged "$untagged" '.networks[] | .lane | select(. > $untagged)'); do
        bridge vlan add dev "$cable" vid "$lane" || ok=no
      done
      if [ "$ok" = yes ]; then
        echo "$cable carries every network of $file."
      else
        echo "$cable does not carry every network of $file: the reason stands above."
        rc=1
      fi
    else
      echo "$cable carries no network of $file: there is no device of that name."
    fi
    ok=yes
    if links=$(ip -j link show master "$switch") && flags=$(printf '%s' "$links" | jq -r --argjson nets "$json" '
        .[] | .ifname as $c | $nets.stations[$c] // empty
        | "\($c) \(if $nets.networks[.network]."reach-each-other" then "off" else "on" end)"'); then
      while read -r station isolated; do
        [ -n "$station" ] || continue
        bridge link set dev "$station" isolated "$isolated" || ok=no
      done <<EOF
    $flags
    EOF
    else
      ok=no
    fi
    if [ "$ok" = yes ]; then
      echo "every VM's cable on $switch follows its network's reach-each-other."
    else
      echo "a VM's cable on $switch does not follow its network's reach-each-other: the reason stands above."
      rc=1
    fi
    exit $rc
  '';

  # The host's uplinks (uplinks.nix): one NetworkManager profile each, named
  # after its entry. the ensure step makes a missing profile and puts
  # the fields the list declares into it; the allowance (never-default, the
  # DNS) and the preference (the route metrics) are gate's at runtime.
  ul = import ./uplinks.nix;
  up = ul.uplinks;
  names = lib.attrNames up;
  vms = lib.filterAttrs (n: u: u.kind == "vm") up;
  # The gate word of the uplink through the VMs: gate with it opens the
  # Wi-Fi VM's Wi-Fi screen, the one thing to do for its Wi-Fi.
  wifiUplink = lib.head (lib.attrNames vms);
  cables = lib.filterAttrs (n: u: u.kind == "ethernet") up;
  # The inner end of the host's cable on the workstations' switch: the
  # device of the uplink of kind "vm".
  inner = (lib.head (lib.attrValues vms)).device;
  # Every uplink's profile is an ethernet profile: nmcli adds it as type
  # ethernet and shows its type back as 802-3-ethernet.
  declared = u: "connection.interface-name ${u.device} connection.autoconnect yes " + (
    if u.kind == "vm" then
      "ipv4.method manual ipv4.addresses ${hostIp}/${toString u.prefix} ipv4.gateway ${u.gateway}"
    else "ipv4.method auto");
  # The DNS an allowed uplink gives the host: the firewall VM on the path
  # through the VMs; on a cable, the one its DHCP server names.
  dns = u: if u.kind == "vm" then u.gateway else "";
  fields = "connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.route-metric,ipv6.route-metric,ipv4.never-default,ipv6.never-default,ipv4.ignore-auto-dns,ipv6.ignore-auto-dns";
  # gate's help: one line per command, "gate WORDS: what it does".
  usage = [
    "gate status: ${lib.concatStringsSep ", " (lib.attrValues hostNetworks.vms)}, the switches and their cables, the uplinks and the way out, seen from the host"
  ] ++ lib.concatLists (lib.mapAttrsToList (n: u: [
    ("gate ${n}: " + (if u.kind == "vm"
      then "${wifiVm}'s Wi-Fi screen (nmtui), then allow ${n}: it may carry the host's route and DNS"
      else "allow ${n}: it may carry the host's route and DNS, by itself whenever plugged in"))
    "gate ${n} off: withdraw ${n}: no route or DNS of the host over it; its link stays up"
  ]) up) ++ [
    "gate prefer NAME: NAME (${lib.concatStringsSep ", " names}) carries the traffic when more than one is allowed and up"
    "gate log [NAME]: ${firewallVm}'s log of NAME (or of all): names asked, connections made and refused"
  ];

  # The shell functions of the uplinks' profiles, for the ensure step and
  # for gate; nmcli through sudo when not run as root.
  uplinksSh = pkgs.writeText "uplinks.sh" ''
    nm() {
      if [ "$(id -u)" = 0 ]; then ${config.networking.networkmanager.package}/bin/nmcli "$@"
      else sudo ${config.networking.networkmanager.package}/bin/nmcli "$@"; fi
    }
    allowed() { [ "$(nm -g ipv4.never-default connection show "$1" 2>/dev/null)" = no ]; }
    active() { nm -g NAME connection show --active | grep -qxF "$1"; }
    # The uplink preferred now: the profile with the lowest route metric;
    # the list's starting value while no profile exists.
    preferred() {
      p=${ul.prefer}; low=
      for n in ${toString names}; do
        m=$(nm -g ipv4.route-metric connection show "$n" 2>/dev/null) || continue
        if [ -z "$low" ] || [ "$m" -lt "$low" ]; then low=$m; p=$n; fi
      done
      echo "$p"
    }
    # apply NAME FIELD VALUE ...: the fields into the profile; an active
    # profile takes a change at once.
    apply() {
      n=$1; shift
      before=$(nm -g ${fields} connection show "$n")
      nm connection modify "$n" "$@" || return 1
      if [ "$(nm -g ${fields} connection show "$n")" != "$before" ] && active "$n"; then
        nm device reapply "$(nm -g connection.interface-name connection show "$n")" >/dev/null \
          || nm connection up "$n" >/dev/null
      fi
    }
  '';

  # The ensure step, one script for the unit uplinks-ensure and for gate:
  # each profile made when missing (withdrawn), the list's fields put into
  # it, the metric pair given by the uplink named as its argument, else by
  # the one preferred now; the allowance is left as it is. A profile of
  # another type (wifi was once a bridge profile) is removed
  # and added again from the list, its allowance carried over.
  ensure = pkgs.writeShellScript "uplinks-ensure" ''
    set -u
    . ${uplinksSh}
    pref=''${1:-$(preferred)}
    ${lib.concatStrings (lib.mapAttrsToList (n: u: ''
    nd=yes
    t=$(nm -g connection.type connection show ${n} 2>/dev/null) || t=
    if [ -n "$t" ] && [ "$t" != 802-3-ethernet ]; then
      if allowed ${n}; then nd=no; fi
      nm connection delete ${n} >/dev/null
    fi
    nm connection show ${n} >/dev/null 2>&1 \
      || nm connection add type ethernet con-name ${n} ${declared u} ipv4.never-default $nd ipv6.never-default $nd ipv4.ignore-auto-dns $nd ipv6.ignore-auto-dns $nd >/dev/null
    if allowed ${n}; then d="${dns u}"; else d=; fi
    if [ "$pref" = ${n} ]; then m=${toString ul.metric.preferred}; else m=${toString ul.metric.others}; fi
    apply ${n} ${declared u} ipv4.dns "$d" ipv4.route-metric "$m" ipv6.route-metric "$m"
    '') up)}'';

  gate = pkgs.writeShellScriptBin "gate" ''
    ${lib.concatMapStrings (l: "# ${l}\n") usage}set -u
    # A command run inside ${wifiVm} over ssh, for gate status. The ssh ends
    # after the seconds of internet-wait (host-networks.nix) when no answer
    # has come; it reads no input (-n), since timeout runs it in a process
    # group of its own, where reading the terminal would stop it.
    ${wifiVm}() {
      sudo ${pkgs.coreutils}/bin/timeout ${toString hostNetworks.internet-wait} \
        ssh -n -i /root/.ssh/${wifiVm} -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=/root/.ssh/known_hosts_${wifiVm} root@vsock/${vmCid wifiVm} "$@"
    }
    . ${uplinksSh}
    # allow NAME yes DNS | allow NAME no: the allowance, the same for every
    # uplink; the profile and its link stay up either way.
    allow() {
      if [ "$2" = yes ]; then nd=no; d=''${3:-}; else nd=yes; d=; fi
      apply "$1" ipv4.never-default $nd ipv6.never-default $nd ipv4.ignore-auto-dns $nd ipv6.ignore-auto-dns $nd ipv4.dns "$d"
      if [ "$2" = yes ] && ! active "$1"; then
        nm connection up "$1" >/dev/null 2>&1 || echo "$1 is not up now; it comes up by itself when its link is there."
      fi
    }
    # The device of the host's default route with the lowest metric; empty
    # when the host has no default route.
    routedev() {
      ip -4 route show default | awk '{ m = 0; for (i = 1; i < NF; i++) { if ($i == "dev") d = $(i + 1); if ($i == "metric") m = $(i + 1) } print m, d }' | sort -n | head -n 1 | cut -d' ' -f2
    }
    # uplinks: the facts of each uplink and of the host's route, one per
    # line in the form status_print names, for gate status and, through
    # status_lines, for gate NAME, gate NAME off and gate prefer.
    uplinks() {
      p=$(preferred)
      for n in ${toString names}; do
        if active "$n"; then u=up; else u=not-up; fi
        if allowed "$n"; then a=allowed; else a=not-allowed; fi
        if [ "$n" = "$p" ]; then echo "uplink $n $u $a preferred"; else echo "uplink $n $u $a other"; fi
      done
      dev=$(routedev)
      case "$dev" in
      ${lib.concatStrings (lib.mapAttrsToList (n: u: "${u.device}) echo \"route ${n}\" ;;\n      ") up)}"") echo "route none" ;;
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
      ${lib.concatMapStrings (s: "${s}) echo ${toString (onSwitch s)} ;;\n      ") (lib.attrValues switches)}esac
    }
    # status_print: the lines of gate status from the facts read from the
    # host, one fact per line on standard input:
    #   vm NAME running | vm NAME stopped
    #   wifi connected PROFILE | wifi not-connected | wifi unreadable
    #   switch NAME up|down CABLE,CABLE,... | switch NAME missing
    #   uplink NAME up|not-up allowed|not-allowed preferred|other
    #   route UPLINK | route none | route other DEVICE
    #   internet yes | internet no
    # The first wrong piece goes on top with what it means and the one thing
    # to do, in this order: a service VM not running; a switch not there or
    # down; a cable not on its switch; ${wifiVm}'s Wi-Fi not connected or
    # not readable; no route of the host; no internet. Then status_lines.
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
          case "$w" in
          "" | connected*) ;;
          not-connected) echo "${wifiVm}'s Wi-Fi is not connected: $(meaning ${wifiVm}). Do: gate ${wifiUplink}" ;;
          *) echo "${wifiVm}'s Wi-Fi cannot be read: $(meaning ${wifiVm}). Do: gate ${wifiUplink}" ;;
          esac
          if printf '%s\n' "$facts" | grep -qx 'route none'; then
            echo "the host's route: none. Do: ${lib.concatMapStringsSep " or " (n: "gate ${n}") names}"
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
        route)
          case "$n" in
          none) echo "the host's route: none" ;;
          other) echo "the host's route: $s, not an uplink of uplinks.nix" ;;
          *) echo "the host's route: $n" ;;
          esac
          ;;
        internet) echo "internet: $n" ;;
        esac
      done
    }
    ${ensure}
    case "''${1:-}" in
    status)
      # The facts, read live: each service VM's unit; inside the running
      # Wi-Fi VM, its Wi-Fi card's state (100: connected) and the saved
      # network it is connected to, one value each, over one ssh that ends
      # after the seconds of internet-wait with no answer, its Wi-Fi then
      # unreadable; each switch of host-networks.nix and the devices on it,
      # from one listing of the host's devices; each uplink; the host's
      # route; the internet.
      {
        for v in ${toString (lib.attrValues hostNetworks.vms)}; do
          if [ "$(systemctl is-active microvm@$v.service)" != active ]; then
            echo "vm $v stopped"
            continue
          fi
          echo "vm $v running"
          if [ "$v" = ${wifiVm} ]; then
            if r=$(${wifiVm} 'nmcli -e no -g GENERAL.STATE device show ${hostNetworks.wifi-card} 2>/dev/null && nmcli -e no -g GENERAL.CONNECTION device show ${hostNetworks.wifi-card} 2>/dev/null'); then
              s=$(printf '%s\n' "$r" | sed -n 1p)
              if [ "''${s%% *}" = 100 ]; then
                echo "wifi connected $(printf '%s\n' "$r" | sed -n 2p)"
              else
                echo "wifi not-connected"
              fi
            else
              echo "wifi unreadable"
            fi
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
        allow ${n} no
      else
        ${lib.optionalString (u.kind == "vm") ''
        sudo ssh -i /root/.ssh/${wifiVm} -o StrictHostKeyChecking=accept-new \
          -o UserKnownHostsFile=/root/.ssh/known_hosts_${wifiVm} -t root@vsock/${vmCid wifiVm} nmtui
        ''}allow ${n} yes "${dns u}"
      fi
      uplinks | status_lines
      ;;
    '') up)}prefer)
      case "''${2:-}" in
      ${lib.concatMapStrings (n: "${n}) ${ensure} ${n} ;; ") names}*) echo "STOP: name an uplink of modules/isolation/uplinks.nix: ${toString names}."; exit 1 ;;
      esac
      uplinks | status_lines
      ;;
    log)
      # NAME's ip: the host's from stations.nix; any other station's from
      # the live data file, read now, so a VM the bastion tool made is found.
      ip=
      if [ "''${2:-}" = ${hostPort} ]; then
        ip=${hostIp}
      elif [ -n "''${2:-}" ]; then
        ip=$(${pkgs.jq}/bin/jq -r --arg n "$2" '.stations[$n].ip // empty' ${networksFile} 2>/dev/null) || ip=
        [ -n "$ip" ] || { echo "STOP: no station '$2' could be read from ${networksFile}."; exit 1; }
      fi
      if [ -n "$ip" ]; then
        sudo journalctl -D ${config.microvm.stateDir}/${firewallVm}/journal/${vmId firewallVm} --no-pager -n 300 -g "(gate|query|reply|forwarded|DHCP).*$ip([^0-9]|$)"
      else
        sudo journalctl -D ${config.microvm.stateDir}/${firewallVm}/journal/${vmId firewallVm} --no-pager -n 300
      fi
      ;;
    *)
      sed -n '2,${toString (lib.length usage + 1)}s/^# //p' "$0"
      ;;
    esac
  '';
in
{
  # networks-apply runs after each service VM's cables are made: Wants= and
  # Before= in a drop-in on microvm.nix's unit microvm-tap-interfaces@VM,
  # the way microvm.nix adds its own drop-ins to that unit; one per VM of
  # host-networks.nix, made by a loop in a module of their own.
  imports = [ {
    systemd.services = lib.genAttrs (map (v: "microvm-tap-interfaces@${v}") (lib.attrValues hostNetworks.vms)) (v: {
      wants = [ "networks-apply.service" ];
      before = [ "networks-apply.service" ];
    });
  } {
    # A veth is unmanaged by NetworkManager's own udev rule
    # (85-nm-unmanaged.rules); a device section with managed outranks it, so
    # the device of each uplink of kind "vm" is managed and its profile comes
    # up by itself at every boot. One section per such uplink, named
    # "device-" and its device; a module of its own, since settings.main is
    # set below in this one.
    networking.networkmanager.settings = lib.mapAttrs' (n: u: lib.nameValuePair "device-${u.device}" {
      match-device = "interface-name:${u.device}";
      managed = true;
    }) vms;
  } ];

  # No memory merging (microvm.nix turns it on by default).
  hardware.ksm.enable = false;

  # Every station's name is its cable's name on the workstations' switch;
  # a service cable's name is its device's name on the host.
  assertions = lib.mapAttrsToList (n: s: {
    assertion = lib.stringLength n <= nameMax;
    message = "modules/isolation/stations.nix: the station ${n} has a name of ${toString (lib.stringLength n)} characters; a station's name is its cable's name, at most ${toString nameMax} characters.";
  }) st ++ map (c: {
    assertion = lib.stringLength c.name <= nameMax;
    message = "modules/isolation/host-networks.nix: the cable ${c.name} has a name of ${toString (lib.stringLength c.name)} characters; a cable's name is its device's name on the host, at most ${toString nameMax} characters.";
  }) (lib.attrValues hostNetworks.cables);

  networking.bridges."${switches.wifi-link}".interfaces = [ ];
  # The port end of the host's cable, attached by NixOS's bridge setup, so
  # a re-made workstations' switch gets it back. It binds the switch's unit
  # (the switch's name and -netdev) to that device: were the device gone,
  # that unit would stop and delete the switch, and so the unit below never
  # deletes the pair.
  networking.bridges."${switches.workstations}".interfaces = [ hostPort ];

  # The two switches carry no address of the host's own networking (the
  # host's address on the VM network is NetworkManager's, on the inner end
  # of the host's cable, from the profile "wifi" of uplinks.nix), so nothing
  # in the dependency graph activates their generated bridge services and
  # the devices are never made. Start them explicitly, or the workstations'
  # cables (libvirt) and the service VMs' cables (networks-apply) find no
  # switch.
  systemd.services."${switches.wifi-link}-netdev".wantedBy = [ "multi-user.target" ];
  systemd.services."${switches.workstations}-netdev".wantedBy = [ "multi-user.target" ];

  # The host's cable on the workstations' switch, a veth pair: the port end
  # on the switch, the inner end NetworkManager's. Made before the switch's
  # unit, which is then the only maker of the switch, and never deleted.
  # Named as NixOS names a unit that makes a device: the device's name and
  # -netdev.
  systemd.services."${hostPort}-netdev" = {
    description = "The host's cable on ${switches.workstations}: ${hostPort} on the bridge, ${inner} the host's";
    wantedBy = [ "${switches.workstations}-netdev.service" ];
    before = [ "${switches.workstations}-netdev.service" ];
    after = [ "network-pre.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      ip link show dev ${hostPort} >/dev/null 2>&1 \
        || ip link add name ${hostPort} type veth peer name ${inner}
    '';
  };

  # networks-apply: the service VMs' cables of host-networks.nix, taps that
  # microvm.nix's unit microvm-tap-interfaces@VM makes on no switch before
  # each VM starts, each put on its switch; then the live data file and the
  # guard built from it (networksApplyFile above). It runs after both
  # switches and every cable are made, and again whenever one of them is
  # made again: it is part of those units, so their stop and restart reach
  # it (a VM's restart makes its cables again), and each switch's unit wants
  # it. A cable put on the switch it is on stays as it is. A cable that is
  # not there is named in its log; the boot goes on. A rebuild leaves the
  # guard to it: the guard is no table of networking.nftables.
  systemd.services.networks-apply = {
    description = "The service VMs' cables of host-networks.nix on their switches, and the guard from the live data file";
    wantedBy = switchUnits;
    partOf = switchUnits ++ tapUnits;
    after = switchUnits ++ tapUnits;
    # Started before firewall-vm, so the file is there when firewall-apply
    # reads it at that VM's start.
    before = [ "microvm@${firewallVm}.service" ];
    path = [ pkgs.iproute2 pkgs.nftables pkgs.jq ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = lib.concatMapStrings (c: ''
      if [ -e /sys/class/net/${c.name} ]; then
        ip link set dev ${c.name} master ${switches.${c.switch}}
      else
        echo "${c.name} is not on ${switches.${c.switch}}: there is no device of that name; its VM is stopped, or no service VM has it in its interfaces."
      fi
    '') (lib.attrValues hostNetworks.cables) + networksApplyFile;
  };

  # The host's address on the VM network, its default route and its DNS:
  # the uplinks' NetworkManager profiles (uplinks.nix).
  # NetworkManager manages each uplink's device: a cable's as it is, the inner
  # end of the host's cable by its device section (imports above), since
  # NetworkManager's own udev rule leaves a veth unmanaged otherwise; and
  # stays away from the switches, the workstations'
  # cables (by their names in stations.nix), the service VMs' cables (by
  # their names in host-networks.nix), the other ports and the port end of
  # the host's cable.
  networking.networkmanager.unmanaged =
    map (n: "interface-name:${n}") (lib.attrValues switches ++ lib.attrNames ws
      ++ map (c: c.name) (lib.attrValues hostNetworks.cables))
    ++ [ "interface-name:tap*" "interface-name:vnet*" "interface-name:virbr*" "interface-name:${hostPort}" ];
  # Each cable's interface gets the name in its device field, found by its
  # USB ids (udev applies .link files with or without systemd-networkd).
  systemd.network.links = lib.mapAttrs' (n: u: lib.nameValuePair "10-${n}" {
    matchConfig.Property = "ID_VENDOR_ID=${u.vendor} ID_MODEL_ID=${u.product}";
    linkConfig.Name = u.device;
  }) cables;
  # No automatic connection for an uplink's device, a cable's or the inner
  # end of the host's cable: only its profile, made from the list, runs on
  # it, and a cable carries nothing until gate allows it.
  networking.networkmanager.settings.main.no-auto-default =
    lib.concatMapStringsSep ";" (u: "interface-name:${u.device}") (lib.attrValues up);
  # The ensure step at activation and at every start, after NetworkManager
  # is up: both profiles exist with the list's values right after the
  # switch; the allowance stays withdrawn until gate.
  systemd.services.uplinks-ensure = {
    description = "The host's uplink profiles of uplinks.nix";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" ];
    path = [ pkgs.coreutils pkgs.gnugrep ];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = "${ensure}";
  };
  # With two uplinks a reply may come in over the one that does not carry
  # the default route: drop a packet only when its source is reachable over
  # no interface at all.
  networking.firewall.checkReversePath = "loose";

  # QEMU's bridge helper may put ports on these bridges: libvirt's own and
  # the two switches. The service VMs do not use it: their cables are taps
  # that networks-apply puts on their switches.
  virtualisation.libvirtd.allowedBridges = [ "virbr0" ] ++ lib.attrValues switches;

  # The guard of the workstations' switch is networks-apply's (above).
  networking.nftables.enable = true;

  # The microVMs' logs, readable on the host with journalctl -m.
  systemd.tmpfiles.rules = map (v:
    "L+ /var/log/journal/${vmId v} - - - - ${config.microvm.stateDir}/${v}/journal/${vmId v}"
  ) (lib.attrValues hostNetworks.vms);

  environment.systemPackages = [ gate pkgs.curl ];
}
