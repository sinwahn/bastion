# /etc/nixos/modules/isolation/broker.nix
# broker-vm: the one VM that owns the exchange of files
# between the VMs. A microVM, started with the host, with no
# network at all: the host reaches it over vsock alone, and no VM reaches
# it. Its names and words come from host-networks.nix.
#   kept copies  every file sent is kept under a folder named after its
#                sender, on a volume of its own in its state folder, until
#                clean deletes it.
#   routes       a station's list of destinations in the live data file
#                (host-networks.nix), read through a read-only share of its
#                folder at each send; a station without one sends nothing.
#   log          every send, delivery, clean and refusal is a line of its
#                journal, kept on the host in the journal folder of its
#                state folder.
#   login        the host's key named after this VM, as root, over vsock;
#                sshd runs only the broker's program, whatever the host
#                asks.
# On the host: the unit that makes the host's two keys, the one for this VM
# and the one for the VMs' exchange accounts, and puts their public halves
# beside the live data file; the host's folder for a file during its send
# and its own inbox.
{ config, lib, pkgs, ... }:

let
  st = import ./stations.nix;
  hostNetworks = import ./host-networks.nix;
  brokerVm = hostNetworks.vms.broker-vm;
  exchange = hostNetworks.exchange;

  # The host's name, a destination only: the one station of stations.nix
  # without a MAC, which the live data file does not hold.
  hostPort = lib.head (lib.attrNames (lib.filterAttrs (n: s: !(s ? mac)) st));

  # The live data file and its folder, shared read-only into this VM at the
  # same path, by the folder's name, as into firewall-vm (gateway.nix).
  networksFile = hostNetworks."networks.json";
  bastionDir = dirOf networksFile;

  # The host's keys: the one for this VM, named after it, in the folder of
  # the exchange key; and the exchange key. Each one's public half goes
  # into the folder of the live data file under the key's file name and
  # .pub.
  brokerKey = "${dirOf exchange.key}/${brokerVm}";
  publicHalf = key: "${bastionDir}/${baseNameOf key}.pub";

  # The mount point of the kept copies' volume inside this VM.
  exchangeDir = "/exchange";
  # sshd's host key lives on a volume of its own at this folder, as net.nix
  # keeps wifi-vm's; on the tmpfs root a fresh key would be made at every
  # boot.
  hostKeysDir = "/var/lib/ssh-host-keys";
  # A take is refused when the kept copies would pass this percent of their
  # volume's size.
  percent = 80;

  # The words of the program, each a shell variable named by its group and
  # its key in the exchange group of host-networks.nix: verbs_ask,
  # log_from, reasons_route and so on.
  words = lib.concatMapStrings (g: lib.concatStrings (lib.mapAttrsToList
    (k: v: "${g}_${k}=${lib.escapeShellArg v}\n") exchange.${g})) [ "verbs" "log" "reasons" ];

  # The broker's program, named after this VM: sshd runs it at every login
  # of the host, whatever command the host gave, which it takes from
  # SSH_ORIGINAL_COMMAND, split at spaces; every file name in it is
  # base64-encoded. It reads the stations and their lists of destinations
  # from the live data file at each command, writes each event into this
  # VM's journal under its own name as a line of the parts known of
  # "EVENT, from FROM, to TO, name NAME, bytes N, sha256 H, reason R", and
  # prints a refusal's line. Its commands, by the verbs of host-networks.nix:
  #   usage      the bytes used on the kept copies' volume, its size and the
  #              limit, the percent above of the size, as the filesystem
  #              reports them
  #   ask FROM TO FILE
  #              exit 0 when FROM's list of destinations names TO
  #   take FROM TO FILE BYTES
  #              as ask, and refused when the kept copies would pass the
  #              limit; else standard input is kept as FROM/STAMP-FILE
  #              (STAMP the UTC time) through a temporary name, refused and
  #              removed when its count is not BYTES; prints the bytes, the
  #              sha256 and that path
  #   done FROM TO FILE DELIVERED
  #              the delivery logged, DELIVERED the name the file got at TO
  #   clean VM   each kept copy of VM logged, then deleted; VM a station of
  #              the live data file or the folder of a VM's kept copies (a
  #              retired VM's); prints the count and the bytes
  # Refused, logged and printed, exit 1: any other command; a file name
  # that holds a slash or a newline or is . or ..; a FROM that is the host
  # or no station; a TO that is neither a station nor the host.
  program = pkgs.writeShellScript brokerVm ''
    export PATH=${lib.makeBinPath [ pkgs.jq pkgs.coreutils pkgs.util-linux ]}
    set -u
    file=${networksFile}
    root=${exchangeDir}
    percent=${toString percent}
    host=${hostPort}
    key=${lib.escapeShellArg exchange.sends-to}
    tag=${brokerVm}
    ${words}
    nl='
    '
    # note EVENT FROM TO NAME BYTES SHA256 REASON: the line of the parts
    # given (an empty one is left out) into the journal under this
    # program's name; it stays in l.
    note() {
      l=$1
      if [ -n "$2" ]; then l="$l, $log_from $2"; fi
      if [ -n "$3" ]; then l="$l, $log_to $3"; fi
      if [ -n "$4" ]; then l="$l, $log_name $4"; fi
      if [ -n "$5" ]; then l="$l, $log_bytes $5"; fi
      if [ -n "$6" ]; then l="$l, $log_sha256 $6"; fi
      if [ -n "$7" ]; then l="$l, $log_reason $7"; fi
      logger -t "$tag" -- "$l"
    }
    # refuse FROM TO NAME BYTES REASON: the refused line logged and printed;
    # exit 1.
    refuse() {
      note "$log_refused" "$1" "$2" "$3" "$4" "" "$5"
      printf '%s\n' "$l"
      exit 1
    }
    # station NAME: NAME is a station of the live data file.
    station() {
      jq -e --arg n "$1" '.stations | has($n)' "$file" >/dev/null 2>&1
    }
    # route FROM TO: FROM's list of destinations names TO.
    route() {
      jq -e --arg f "$1" --arg t "$2" --arg k "$key" '.stations[$f][$k] // [] | any(.[]; . == $t)' "$file" >/dev/null 2>&1
    }
    # badname NAME: NAME holds a slash or a newline, or is . or ..
    badname() {
      case "$1" in
      . | .. | */* | *"$nl"*) return 0 ;;
      esac
      return 1
    }
    # decode TEXT: d, the name base64-encoded in TEXT, a newline at its end
    # kept.
    decode() {
      d=$(printf '%s' "$1" | base64 -d; printf x)
      d=''${d%x}
    }
    # check FROM TO NAME BYTES: the names, each refusal with the parts given.
    check() {
      if badname "$3"; then refuse "$1" "$2" "$3" "$4" "$reasons_file"; fi
      if [ "$1" = "$host" ]; then refuse "$1" "$2" "$3" "$4" "$reasons_host"; fi
      if ! station "$1"; then refuse "$1" "$2" "$3" "$4" "$reasons_station"; fi
      if [ "$2" != "$host" ] && ! station "$2"; then refuse "$1" "$2" "$3" "$4" "$reasons_station"; fi
    }
    # space: used and size, the bytes used on the kept copies' volume and
    # its size as the filesystem reports them, and limit, percent of size.
    space() {
      set -- $(df -B1 --output=used,size "$root" | tail -n 1)
      used=$1 size=$2 limit=$(($2 * percent / 100))
    }
    set -f
    set -- ''${SSH_ORIGINAL_COMMAND:-}
    set +f
    verb=''${1:-}
    if [ $# -gt 0 ]; then shift; fi
    case "$verb" in
    "$verbs_usage")
      if [ $# != 0 ]; then refuse "" "" "" "" "$reasons_command"; fi
      space
      printf '%s, %s, %s\n' "$used" "$size" "$limit"
      ;;
    "$verbs_ask")
      if [ $# != 3 ]; then refuse "" "" "" "" "$reasons_command"; fi
      decode "$3"
      check "$1" "$2" "$d" ""
      if ! route "$1" "$2"; then refuse "$1" "$2" "$d" "" "$reasons_route"; fi
      ;;
    "$verbs_take")
      if [ $# != 4 ]; then refuse "" "" "" "" "$reasons_command"; fi
      from=$1 to=$2 bytes=$4
      decode "$3"
      name=$d
      check "$from" "$to" "$name" "$bytes"
      if ! route "$from" "$to"; then refuse "$from" "$to" "$name" "$bytes" "$reasons_route"; fi
      space
      if [ $((used + bytes)) -gt "$limit" ]; then refuse "$from" "$to" "$name" "$bytes" "$reasons_full"; fi
      stamp=$(date -u +%Y%m%dT%H%M%SZ)
      mkdir -p "$root/$from"
      tmp=$(mktemp "$root/$from/$stamp.XXXXXX")
      cat > "$tmp"
      count=$(wc -c < "$tmp")
      if [ "$count" != "$bytes" ]; then
        rm -f "$tmp"
        refuse "$from" "$to" "$name" "$count" "$reasons_count"
      fi
      sum=$(sha256sum < "$tmp")
      sum=''${sum%% *}
      kept=$from/$stamp-$name
      mv "$tmp" "$root/$kept"
      note "$log_taken" "$from" "$to" "$name" "$count" "$sum" ""
      printf '%s, %s, %s\n' "$count" "$sum" "$kept"
      ;;
    "$verbs_done")
      if [ $# != 4 ]; then refuse "" "" "" "" "$reasons_command"; fi
      decode "$3"
      name=$d
      decode "$4"
      if badname "$name"; then refuse "$1" "$2" "$d" "" "$reasons_file"; fi
      check "$1" "$2" "$d" ""
      note "$log_delivered" "$1" "$2" "$d" "" "" ""
      ;;
    "$verbs_clean")
      if [ $# != 1 ]; then refuse "" "" "" "" "$reasons_command"; fi
      vm=$1
      if ! station "$vm" && { badname "$vm" || [ ! -d "$root/$vm" ]; }; then
        refuse "$vm" "" "" "" "$reasons_station"
      fi
      count=0 bytes=0
      for f in "$root/$vm"/*; do
        if [ ! -f "$f" ]; then continue; fi
        n=$(wc -c < "$f")
        sum=$(sha256sum < "$f")
        note "$log_cleaned" "$vm" "" "''${f##*/}" "$n" "''${sum%% *}" ""
        rm -f "$f"
        count=$((count + 1)) bytes=$((bytes + n))
      done
      printf '%s, %s\n' "$count" "$bytes"
      ;;
    *)
      refuse "" "" "" "" "$reasons_command"
      ;;
    esac
  '';
in
{
  microvm.vms.${brokerVm}.config = {
    system.stateVersion = "26.05";

    microvm = {
      hypervisor = "qemu";
      vcpu = 1;
      mem = 512;
      # No network interface (interfaces stays empty): the host reaches this
      # VM over vsock alone.
      volumes = [ {
        image = "exchange.img";
        mountPoint = exchangeDir;
        size = 20480;
      }
      {
        image = "ssh-host-keys.img";
        mountPoint = hostKeysDir;
        size = 16;
      } ];
      shares = [ {
        proto = "virtiofs";
        tag = "journal";
        socket = "journal.sock";
        source = "${config.microvm.stateDir}/${brokerVm}/journal";
        mountPoint = "/var/log/journal";
      }
      {
        proto = "virtiofs";
        tag = baseNameOf bastionDir;
        source = bastionDir;
        mountPoint = bastionDir;
        readOnly = true;
      } ];
      vsock.cid = 12;
      vsock.ssh.enable = true;
    };

    # The journal keeps at most this much; the oldest lines go first.
    services.journald.extraConfig = "SystemMaxUse=1G";

    # Only the host reaches this VM's login, over vsock (no network), with
    # its key named after this VM, whose public half sshd reads from the
    # shared folder; sshd runs the broker's program and nothing else.
    services.openssh.listenAddresses = [ { addr = "127.0.0.1"; port = 22; } ];
    services.openssh.hostKeys = [ { type = "ed25519"; path = "${hostKeysDir}/ssh_host_ed25519_key"; } ];
    # NixOS adds the home folder's file and its own folder's file to this
    # list; the one file stands alone only when forced.
    services.openssh.authorizedKeysFiles = lib.mkForce [ (publicHalf brokerKey) ];
    services.openssh.extraConfig = ''
      AllowUsers root
      ForceCommand ${program}
      PermitTTY no
      DisableForwarding yes
    '';
  };

  # The host's two keys, each made when missing (ed25519, no passphrase),
  # and each public half put into the folder of the live data file, root's
  # and 0644, when it is missing there or differs; before broker-vm starts,
  # whose sshd reads the public half of the key named after it.
  systemd.services."${brokerVm}-keys" = {
    description = "The host's keys for ${brokerVm} and for the VMs' exchange accounts, their public halves in ${bastionDir}";
    wantedBy = [ "multi-user.target" ];
    before = [ "microvm@${brokerVm}.service" ];
    path = [ pkgs.openssh pkgs.coreutils pkgs.diffutils ];
    serviceConfig.Type = "oneshot";
    script = lib.concatMapStrings (key: ''
      if [ ! -e ${key} ]; then
        ssh-keygen -q -t ed25519 -N "" -f ${key}
      fi
      if ! cmp -s ${key}.pub ${publicHalf key}; then
        install -o root -g root -m 0644 ${key}.pub ${publicHalf key}
      fi
    '') [ brokerKey exchange.key ];
  };

  # The host's folder for a file during its send and its own inbox, root's
  # alone.
  systemd.tmpfiles.rules = map (d: "d ${d} 0700 root root -") [ exchange.staging exchange.inbox ];
}
