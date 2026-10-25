# /etc/nixos/modules/isolation/gateway.nix
# The firewall VM: nftables and dnsmasq, a rule per
# workstation, every workstation's and the host's only way out. A microVM,
# started with the host. The rules per workstation, the
# listed sets and dnsmasq's hosts are firewall-apply's, from the live data
# file of host-networks.nix, read through a read-only share of its folder;
# the fixed rules and the host's own line stay here. Its names come
# from host-networks.nix; a cable inside it is named after where it leads:
#   toward the Wi-Fi VM      10.199.0.2 on the switch between the two VMs,
#                            to the Wi-Fi VM (10.199.0.1)
#   toward the workstations  10.200.0.1 on the workstations' switch, to the
#                            workstations and the host
# Every other network of the live data file is a VLAN on that same cable:
# firewall-apply makes a leg for it on top of the leg toward the
# workstations, named by the network, with the first address of its range.
# Its log (names asked, connections made and refused) is kept on the host
# in the journal folder of its state folder; "gate log" shows it.
# firewall-check answers the bastion tool's path check over vsock: one VM's
# leg, its line, its last refused tries and the internet from this VM, read
# only.
{ config, lib, pkgs, ... }:

let
  st = import ./stations.nix;
  hostNetworks = import ./host-networks.nix;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  # The Wi-Fi VM's address on the switch between the two VMs: this VM's
  # route out, dnsmasq's server and this VM's own nameserver.
  wifiVmAddress = "10.199.0.1";
  workstations = hostNetworks.switches.workstations;
  # The host: the one station of stations.nix without a MAC; its own line
  # stays here.
  hostStation = lib.filterAttrs (n: s: !(s ? mac)) st;
  table = "gate";
  # The chain of the per-workstation lines, firewall-apply's.
  chain = "stations";
  # The set of every network's leg, by name: the input, the DNS redirect and
  # the logged drop hold for each; the leg toward the workstations until
  # firewall-apply fills it.
  networksSet = "networks";
  # The prefix of the logged drop's line in this VM's journal: a refused
  # try of a VM; firewall-check finds a VM's refused tries by it.
  refusedPrefix = "gate refused ";

  ruleLine = name: s:
    if s.rule == "open" then
      ''iifname "${workstations}" oifname "${wifiVm}" ip saddr ${s.ip} ct state new log prefix "gate ${name} " accept''
    else "";

  # The live data file on the host and its folder, shared read-only into
  # this VM at the same path, by the folder's name.
  networksFile = hostNetworks."networks.json";
  bastionDir = dirOf networksFile;

  # firewall-apply: its folder (systemd's state folder of its units, made
  # before they run) holds dnsmasq's hosts file and its configuration folder.
  apply = "firewall-apply";
  applyDir = "/var/lib/${apply}";
  hostsFile = "${applyDir}/dhcp-hosts";
  confDir = "${applyDir}/conf.d";
  # The vsock port the host connects to for a run of firewall-apply.
  applyPort = 51403;
  vsockCid = 11;

  # firewall-apply reads the file once, refuses it whole when it does not
  # hold what the rules need (the reason in the journal, the rules loaded
  # before stay), makes the leg of each network other than the workstations'
  # that is not there yet (a VLAN on the leg toward the workstations, its id
  # the network's lane, its address the first of the network's range; a leg
  # there stays as it is), then in one nft run, which the kernel applies
  # whole or not at all: refills the set of the networks' legs, empties the
  # chain of the per-workstation lines, deletes the listed sets no station
  # needs any more, adds the ones missing (a set kept keeps the addresses
  # dnsmasq put in it), and writes one line per station (open: the whole
  # internet; listed: the addresses of its names; none: no line, so the
  # logged drop). Then dnsmasq's hosts file (one line per
  # station) and its configuration file (each network's dhcp-range, each
  # other network's leg to listen on, each listed name's set): a changed
  # hosts file is re-read on a signal, a changed configuration file on a
  # restart of dnsmasq.
  firewallApply = pkgs.writeShellScript apply ''
    set -u
    file=${networksFile}
    dir=${applyDir}
    hosts=${hostsFile}
    conf=${confDir}/${apply}.conf
    table=${table}
    chain=${chain}
    set=${networksSet}
    home=${workstations}
    listed=listed_
    up=${wifiVm}
    mkdir -p "$(dirname "$conf")"
    if [ ! -e "$hosts" ]; then
      : > "$hosts"
      chmod 0644 "$hosts"
    fi
    if ! json=$(cat "$file"); then
      echo "$file cannot be read: nothing changed." >&2
      exit 1
    fi
    if ! printf '%s' "$json" | jq '
        if (.networks | type) != "object" then error("networks is not a set of networks")
        elif (.stations | type) != "object" then error("stations is not a set of stations")
        else . end
        | .networks as $nets
        | (.networks | to_entries[] | .key as $n | .value
          | if (."ip-range" | type) != "string" or (."ip-range" | test("^[0-9]{1,3}([.][0-9]{1,3}){3}/[0-9]{1,2}$") | not)
            then error("network \($n): ip-range \(."ip-range") is not an IPv4 range")
            elif (.lane | type) != "number" or .lane != (.lane | trunc) or .lane < 1 or .lane > 4094
            then error("network \($n): lane \(.lane) is not a whole number from 1 to 4094")
            else empty end),
          (.stations | to_entries[] | .key as $n | .value
          | if (.network | type) != "string" or $nets[.network] == null then error("station \($n): its network is not in networks")
            elif (.mac | type) != "string" or (.mac | test("^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$") | not) then error("station \($n): mac is not a MAC")
            elif (.ip | type) != "string" or (.ip | test("^[0-9]{1,3}([.][0-9]{1,3}){3}$") | not) then error("station \($n): ip is not an IPv4 address")
            elif ([.rule] | inside(["open", "listed", "none"]) | not) then error("station \($n): rule is not open, listed or none")
            elif (.names // [] | type) != "array" or ((.names // []) | map(type == "string" and test("^[A-Za-z0-9.-]+$")) | all | not) then error("station \($n): names is not a list of names")
            else empty end)' >/dev/null; then
      echo "$file is refused whole: the reason stands above; the rules loaded before stay." >&2
      exit 1
    fi
    # Each leg: its name, its VLAN id and its address with the range's
    # prefix, the first address of the range (the range's network address,
    # whose last octet is even for any prefix up to 31, plus one).
    legs=$(printf '%s' "$json" | jq -r --arg home "$home" '
        .networks | to_entries[] | select(.key != $home) | .key as $n | .value.lane as $id
        | (.value."ip-range" | split("/")) as [$a, $p] | ($p | tonumber) as $p
        | ($a | split(".") | map(tonumber)) as $o
        | [range(4) as $i | ([[$p - 8 * $i, 8] | min, 0] | max) as $b | $o[$i] - ($o[$i] % pow(2; 8 - $b))]
        | .[3] += 1
        | "\($n) \($id) \(map(tostring) | join("."))/\($p)"')
    while read -r leg id addr; do
      if [ -z "$leg" ] || ip link show dev "$leg" >/dev/null 2>&1; then continue; fi
      if ! { ip link add link "$home" name "$leg" type vlan id "$id" \
          && ip address add "$addr" dev "$leg" && ip link set dev "$leg" up; }; then
        echo "the leg $leg could not be made: the reason stands above; the rules loaded before stay." >&2
        exit 1
      fi
      echo "the leg $leg is made: $addr." >&2
    done <<EOF
    $legs
    EOF
    have=$(nft -t list table inet "$table" | sed -n "s/^[[:space:]]*set \($listed[^ ]*\) {\$/\1/p")
    if ! rules=$(printf '%s' "$json" | jq -r --arg table "$table" --arg chain "$chain" --arg set "$set" --arg listed "$listed" --arg up "$up" --arg have "$have" '
        ($have | split("\n") | map(select(. != ""))) as $old
        | [.stations | to_entries[] | select(.value.rule == "listed") | $listed + (.key | gsub("-"; "_"))] as $new
        | "flush set inet \($table) \($set)",
          "add element inet \($table) \($set) { \(.networks | keys_unsorted | map("\"" + . + "\"") | join(", ")) }",
          "flush chain inet \($table) \($chain)",
          ($old[] | select(. as $s | $new | any(. == $s) | not) | "delete set inet \($table) \(.)"),
          ($new[] | select(. as $s | $old | any(. == $s) | not) | "add set inet \($table) \(.) { type ipv4_addr; flags timeout; timeout 1h; }"),
          (.stations | to_entries[] | .key as $n | .value
           | if .rule == "open" then
               "add rule inet \($table) \($chain) iifname \"\(.network)\" oifname \"\($up)\" ip saddr \(.ip) ct state new log prefix \"gate \($n) \" accept"
             elif .rule == "listed" then
               "add rule inet \($table) \($chain) iifname \"\(.network)\" oifname \"\($up)\" ip saddr \(.ip) ip daddr @\($listed + ($n | gsub("-"; "_"))) ct state new log prefix \"gate \($n) \" accept"
             else empty end)'); then
      echo "the rules could not be built from $file: nothing changed." >&2
      exit 1
    fi
    if ! printf '%s\n' "$rules" | nft -f -; then
      echo "the rules from $file were not loaded: the reason stands above; the rules loaded before stay." >&2
      exit 1
    fi
    reload=no
    restart=no
    tmp=$(mktemp "$hosts.XXXXXX")
    printf '%s' "$json" | jq -r '.stations | to_entries[] | "\(.value.mac),\(.value.ip),\(.key)"' > "$tmp"
    chmod 0644 "$tmp"
    if cmp -s "$tmp" "$hosts"; then rm -f "$tmp"; else mv "$tmp" "$hosts"; reload=yes; fi
    tmp=$(mktemp "$dir/$(basename "$conf").XXXXXX")
    printf '%s' "$json" | jq -r --arg table "$table" --arg listed "$listed" --arg home "$home" '
        (.networks[] | ."ip-range" | split("/") as [$a, $p] | ($p | tonumber) as $p
         | [range(4) as $i | ([[$p - 8 * $i, 8] | min, 0] | max) as $b | 256 - pow(2; 8 - $b) | tostring] | join(".")
         | "dhcp-range=\($a),static,\(.),12h"),
        (.networks | keys_unsorted[] | select(. != $home) | "interface=\(.)"),
        (.stations | to_entries[] | select(.value.rule == "listed") | .key as $n | (.value.names // [])[]
         | "nftset=/\(.)/4#inet#\($table)#\($listed + ($n | gsub("-"; "_")))")' > "$tmp"
    chmod 0644 "$tmp"
    if [ -e "$conf" ] && cmp -s "$tmp" "$conf"; then rm -f "$tmp"; else mv "$tmp" "$conf"; restart=yes; fi
    if systemctl is-active --quiet dnsmasq.service; then
      if [ "$restart" = yes ]; then systemctl restart dnsmasq.service
      elif [ "$reload" = yes ]; then systemctl reload dnsmasq.service; fi
    fi
    echo "the rules, the listed sets and dnsmasq's hosts are loaded from $file."
  '';

  # firewall-check: one VM's facts for the bastion tool's path check, read
  # only: it changes nothing. It reads the VM's name from the connection,
  # takes its network, address, rule and names from the file, and prints one
  # fact per line: its network's leg ("leg NET up", "down", or "missing"
  # when there is no device of that name); its line in the chain of the
  # per-workstation lines, found by its address ("line LOADED RULE COUNT":
  # the kind loaded, open, listed (a line with a listed set) or none (no
  # line), then its rule in the file and the count of its names); its last
  # 5 refused tries from this VM's journal, newest first ("tried TIME
  # ADDRESS", and the name dnsmasq answered that address with to its address
  # where it did); then, last, whether the internet address of
  # host-networks.nix answers within its wait ("internet yes" or "no"), any
  # answer counting, as gate checks it. A name not in the file gives
  # "unknown NAME" in place of the first three.
  checkPort = 60093;
  firewallCheck = pkgs.writeShellScript "firewall-check" ''
    set -u
    file=${networksFile}
    table=${table}
    chain=${chain}
    refused=${lib.escapeShellArg refusedPrefix}
    IFS= read -r name || true
    if ! station=$(jq -er --arg n "$name" '.stations[$n] // empty | "\(.network) \(.ip) \(.rule) \(.names // [] | length)"' "$file" 2>/dev/null); then
      echo "unknown $name"
    else
      set -- $station
      net=$1 ip=$2 rule=$3 count=$4
      if link=$(ip -j link show dev "$net" 2>/dev/null); then
        if [ "$(printf '%s' "$link" | jq -r '.[0].operstate')" = UP ]; then
          echo "leg $net up"
        else
          echo "leg $net down"
        fi
      else
        echo "leg $net missing"
      fi
      line=$(nft list chain inet "$table" "$chain" | grep -F "ip saddr $ip ")
      case "$line" in
      "") loaded=none ;;
      *" ip daddr @"*) loaded=listed ;;
      *) loaded=open ;;
      esac
      echo "line $loaded $rule $count"
      at=$(printf '%s' "$ip" | sed 's/[.]/\\./g')
      journalctl -q --no-pager -o short-iso _TRANSPORT=kernel -n 5 -g "^''${refused}IN=.* SRC=$at DST=" \
        | while read -r time rest; do
            dst=''${rest##* DST=}
            dst=''${dst%% *}
            to=$(printf '%s' "$dst" | sed 's/[.]/\\./g')
            asked=$(journalctl -q --no-pager -o cat -u dnsmasq.service -n 1 \
              -g "^[0-9]+ $at/[0-9]+ (reply|cached|cached-stale) [^ ]+ is $to\$")
            asked=''${asked#* * * }
            asked=''${asked%% *}
            echo "tried $time $dst''${asked:+ $asked}"
          done
    fi
    if curl -s -m ${toString hostNetworks.internet-wait} -o /dev/null ${lib.escapeShellArg hostNetworks.internet}; then
      echo "internet yes"
    else
      echo "internet no"
    fi
  '';

  ruleset = ''
    table inet ${table} {
      # Every network's leg, by name, filled by firewall-apply.
      set ${networksSet} {
        typeof iifname
        elements = { "${workstations}" }
      }

      chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        ct state established,related accept
        iifname @${networksSet} udp dport { 53, 67 } accept
        iifname @${networksSet} tcp dport 53 accept
        log prefix "gate refused-in " drop
      }

      chain dns {
        type nat hook prerouting priority dstnat;
        iifname @${networksSet} udp dport 53 redirect to :53
        iifname @${networksSet} tcp dport 53 redirect to :53
      }

      # The per-workstation lines, filled by firewall-apply.
      chain ${chain} {
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
    ${lib.concatStrings (lib.mapAttrsToList (n: s: "    " + ruleLine n s + "\n") hostStation)}
        jump ${chain}
        iifname @${networksSet} log prefix "${refusedPrefix}" drop
      }

      chain out {
        type nat hook postrouting priority srcnat;
        oifname "${wifiVm}" masquerade
      }
    }
  '';
in
{
  microvm.vms.${firewallVm}.config = {
    system.stateVersion = "26.05";

    microvm = {
      hypervisor = "qemu";
      vcpu = 1;
      mem = 512;
      interfaces = [
        { type = "tap"; id = hostNetworks.cables.firewall-wifi.name; mac = "02:00:00:0a:00:02"; }
        { type = "tap"; id = hostNetworks.cables.firewall-vm.name; mac = "02:00:00:0a:00:03"; }
      ];
      shares = [ {
        proto = "virtiofs";
        tag = "journal";
        socket = "journal.sock";
        source = "${config.microvm.stateDir}/${firewallVm}/journal";
        mountPoint = "/var/log/journal";
      }
      {
        proto = "virtiofs";
        tag = baseNameOf bastionDir;
        source = bastionDir;
        mountPoint = bastionDir;
        readOnly = true;
      } ];
      vsock.cid = vsockCid;
    };

    # firewall-apply at every start of this VM: after nftables made the
    # chain of the per-workstation lines and the share is mounted, before
    # dnsmasq reads the files it writes.
    systemd.services.${apply} = {
      description = "The per-workstation rules, listed sets and DHCP hosts from ${networksFile}";
      wantedBy = [ "multi-user.target" ];
      after = [ "nftables.service" ];
      before = [ "dnsmasq.service" ];
      unitConfig.RequiresMountsFor = [ bastionDir ];
      path = [ pkgs.nftables pkgs.jq pkgs.iproute2 ];
      serviceConfig.Type = "oneshot";
      serviceConfig.StateDirectory = apply;
      serviceConfig.ExecStart = "${firewallApply}";
    };
    # firewall-apply when the host connects to the vsock port: one run per
    # connection, its closing line back to the host, its reasons in the journal.
    systemd.sockets.${apply} = {
      description = "A run of firewall-apply for each connection of the host";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "vsock::${toString applyPort}" ];
      socketConfig.Accept = true;
    };
    systemd.services."${apply}@" = {
      description = "A run of firewall-apply for a connection of the host";
      after = [ "nftables.service" ];
      unitConfig.RequiresMountsFor = [ bastionDir ];
      path = [ pkgs.nftables pkgs.jq pkgs.iproute2 ];
      serviceConfig.StateDirectory = apply;
      serviceConfig.ExecStart = "${firewallApply}";
      serviceConfig.StandardInput = "socket";
      serviceConfig.StandardOutput = "socket";
      serviceConfig.StandardError = "journal";
    };
    # firewall-check when the host connects to its vsock port: one run per
    # connection, its facts back to the host, its errors in the journal.
    systemd.sockets.firewall-check = {
      description = "A run of firewall-check for each connection of the host";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "vsock::${toString checkPort}" ];
      socketConfig.Accept = true;
    };
    systemd.services."firewall-check@" = {
      description = "One VM's facts for the bastion tool's path check, read only";
      unitConfig.RequiresMountsFor = [ bastionDir ];
      path = [ pkgs.nftables pkgs.jq pkgs.iproute2 pkgs.curl ];
      serviceConfig.ExecStart = "${firewallCheck}";
      serviceConfig.StandardInput = "socket";
      serviceConfig.StandardOutput = "socket";
      serviceConfig.StandardError = "journal";
    };

    systemd.network.enable = true;
    networking.useDHCP = false;
    systemd.network.links."10-${wifiVm}" = {
      matchConfig.MACAddress = "02:00:00:0a:00:02";
      linkConfig.Name = wifiVm;
    };
    systemd.network.links."10-${workstations}" = {
      matchConfig.MACAddress = "02:00:00:0a:00:03";
      linkConfig.Name = workstations;
    };
    systemd.network.networks."10-${wifiVm}" = {
      matchConfig.Name = wifiVm;
      address = [ "10.199.0.2/24" ];
      routes = [ { Gateway = wifiVmAddress; } ];
      networkConfig.IPv6AcceptRA = false;
      linkConfig.RequiredForOnline = "routable";
    };
    systemd.network.networks."10-${workstations}" = {
      matchConfig.Name = workstations;
      address = [ "10.200.0.1/24" ];
      networkConfig.IPv6AcceptRA = false;
    };
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;

    networking.firewall.enable = false;
    networking.nftables.enable = true;
    networking.nftables.ruleset = ruleset;

    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        interface = workstations;
        bind-dynamic = true;
        no-resolv = true;
        server = [ wifiVmAddress ];
        domain-needed = true;
        bogus-priv = true;
        dhcp-authoritative = true;
        # firewall-apply's files: the hosts (re-read on a signal) and the
        # configuration folder with each network's dhcp-range, each other
        # network's leg to listen on and each listed name's set (read at a
        # start). No router or DNS server option: dnsmasq hands each leg's
        # own address as both.
        dhcp-hostsfile = hostsFile;
        conf-dir = confDir;
        log-queries = "extra";
        log-dhcp = true;
      };
    };
    # This VM's own lookups (firewall-check's request for the path check) go
    # where the workstations' lookups go: to the server dnsmasq forwards to.
    # systemd-resolved, on with systemd-networkd, takes the nameservers as
    # its DNS.
    networking.nameservers = [ wifiVmAddress ];
  };

  # Copy to read: in /etc/bastion, named after this VM.
  environment.etc."bastion/${firewallVm}.nft".text = ruleset;
}
