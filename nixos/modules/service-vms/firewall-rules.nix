# The firewall VM's rules: the fixed rule set with the host's own line;
# firewall-apply fills it from the live data file, read through a
# read-only share of its folder; firewall-check reads it for the bastion
# tool's path check. The three share the rule set's names.
{ config, lib, pkgs, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  wifiVm = hostNetworks.vms.wifi-vm;
  firewallVm = hostNetworks.vms.firewall-vm;
  workstations = hostNetworks.switches.workstations;
  liveDataFile = hostNetworks."networks.json";
  liveDataFolder = dirOf liveDataFile;
  inherit (import ../networks/station-roles.nix { inherit lib; }) hostStations;
  ruleSet = import ./service-vm-rule-set.nix;
  kTable = "gate";
  kStationsChain = "stations";
  kNetworksSet = "networks";
  kRefusedPrefix = "gate refused ";
  hostRuleLine = name: s:
    if s.rule == "open" then
      ''iifname "${workstations}" oifname "${wifiVm}" ip saddr ${s.ip} ct state new log prefix "gate ${name} " accept''
    else "";
  kApply = "firewall-apply";
  # systemd's state folder of firewall-apply's units, made before they run.
  kApplyFolder = "/var/lib/${kApply}";
  kHostsFile = "${kApplyFolder}/dhcp-hosts";
  kConfigFolder = "${kApplyFolder}/conf.d";
  kApplyPort = 51403;
  firewallApply = pkgs.writeShellScript kApply (''
    set -u
    file=${liveDataFile}
    dir=${kApplyFolder}
    hosts=${kHostsFile}
    conf=${kConfigFolder}/${kApply}.conf
    table=${kTable}
    chain=${kStationsChain}
    set=${kNetworksSet}
    home=${workstations}
    listed=listed_
    up=${wifiVm}
  '' + builtins.readFile ../scripts/firewall-apply.sh);
  kFirewallCheckPort = 60093;
  firewallCheck = pkgs.writeShellScript "firewall-check" ''
    set -u
    file=${liveDataFile}
    table=${kTable}
    chain=${kStationsChain}
    refused=${lib.escapeShellArg kRefusedPrefix}
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
    table inet ${kTable} {
      # Every network's leg, by name, filled by firewall-apply.
      set ${kNetworksSet} {
        typeof iifname
        elements = { "${workstations}" }
      }

      chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        ct state established,related accept
        iifname @${kNetworksSet} udp dport { 53, 67 } accept
        iifname @${kNetworksSet} tcp dport 53 accept
        log prefix "gate refused-in " drop
      }

      chain dns {
        type nat hook prerouting priority dstnat;
        iifname @${kNetworksSet} udp dport 53 redirect to :53
        iifname @${kNetworksSet} tcp dport 53 redirect to :53
      }

      # The per-workstation lines, filled by firewall-apply.
      chain ${kStationsChain} {
      }

      chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
    ${lib.concatStrings (lib.mapAttrsToList (n: s: "    " + hostRuleLine n s + "\n") hostStations)}
        jump ${kStationsChain}
        iifname @${kNetworksSet} log prefix "${kRefusedPrefix}" drop
      }

      chain out {
        type nat hook postrouting priority srcnat;
        oifname "${wifiVm}" masquerade
      }
    }
  '';
in
{
  config = lib.mkMerge [
    (ruleSet firewallVm ruleset)
    {
      microvm.vms.${firewallVm}.config = {
        # At every start, after nftables made the chain of the
        # per-workstation lines and the share is mounted, before dnsmasq
        # reads the files it writes.
        systemd.services.${kApply} = {
          description = "The per-workstation rules, listed sets and DHCP hosts from ${liveDataFile}";
          wantedBy = [ "multi-user.target" ];
          after = [ "nftables.service" ];
          before = [ "dnsmasq.service" ];
          unitConfig.RequiresMountsFor = [ liveDataFolder ];
          path = [ pkgs.nftables pkgs.jq pkgs.iproute2 ];
          serviceConfig.Type = "oneshot";
          serviceConfig.StateDirectory = kApply;
          serviceConfig.ExecStart = "${firewallApply}";
        };
        # One run per connection of the host, its closing line back to the
        # host, its reasons in the journal.
        systemd.sockets.${kApply} = {
          description = "A run of firewall-apply for each connection of the host";
          wantedBy = [ "sockets.target" ];
          listenStreams = [ "vsock::${toString kApplyPort}" ];
          socketConfig.Accept = true;
        };
        systemd.services."${kApply}@" = {
          description = "A run of firewall-apply for a connection of the host";
          after = [ "nftables.service" ];
          unitConfig.RequiresMountsFor = [ liveDataFolder ];
          path = [ pkgs.nftables pkgs.jq pkgs.iproute2 ];
          serviceConfig.StateDirectory = kApply;
          serviceConfig.ExecStart = "${firewallApply}";
          serviceConfig.StandardInput = "socket";
          serviceConfig.StandardOutput = "socket";
          serviceConfig.StandardError = "journal";
        };
        systemd.sockets.firewall-check = {
          description = "A run of firewall-check for each connection of the host";
          wantedBy = [ "sockets.target" ];
          listenStreams = [ "vsock::${toString kFirewallCheckPort}" ];
          socketConfig.Accept = true;
        };
        systemd.services."firewall-check@" = {
          description = "One VM's facts for the bastion tool's path check, read only";
          unitConfig.RequiresMountsFor = [ liveDataFolder ];
          path = [ pkgs.nftables pkgs.jq pkgs.iproute2 pkgs.curl ];
          serviceConfig.ExecStart = "${firewallCheck}";
          serviceConfig.StandardInput = "socket";
          serviceConfig.StandardOutput = "socket";
          serviceConfig.StandardError = "journal";
        };
        # A changed hosts file is re-read on a signal, a changed
        # configuration folder at a restart of dnsmasq.
        services.dnsmasq.settings.dhcp-hostsfile = kHostsFile;
        services.dnsmasq.settings.conf-dir = kConfigFolder;
      };
    }
  ];
}
