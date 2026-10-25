# /etc/nixos/modules/bastion/bastion.nix
# The bastion tool: the command "bastion" on the host, an interactive terminal
# program (bastion.py and guards.py beside this file, Python with textual)
# that makes and changes the VMs without editing a file and without a
# rebuild. The VMs live in libvirt's own store (/var/lib/libvirt/qemu); each
# VM's address and internet rule live in the live data file of
# host-networks.nix, applied by networks-apply (host.nix) and firewall-apply
# (gateway.nix). This file holds only the host's own setup:
# - the templates (the template list) and the host's share;
# - the program and the settings it is handed (a JSON file, its first
#   argument);
# - the copy folder in the owner's home, where the program writes every VM's
#   definition and the copy of networks.json after every change;
# - the store folder of the virtio ISO's viosock folder, which the program's
#   exchange-files copies for the presets module of the exchange, and the
#   exchange's words of host-networks.nix written as JSON to
#   /etc/<command>/exchange.json, where presets/attach.sh reads them;
# - the store folder of the virtio driver folders for the devices of the
#   program's VMs, which the program's virtio-files copies for the presets
#   module repair;
# - the seven steps that need root, which the program runs through sudo:
#     networks-write  writes networks.json and has networks-apply and
#                     firewall-apply apply it;
#     disk-grow       grows an off VM's disk;
#     disk-retire     moves a retired VM's disk, definition, firmware
#                     variables and TPM state into the folder retired;
#     make-disk       a template's empty disk with the virtio ISO, and its
#                     Windows .iso copied in place from the download it is
#                     given, or a copy of a sealed template as a new VM's
#                     disk;
#     template-seal   writes a template's sealed mark.
#   The sixth, state-copy, copies a VM's firmware variables and TPM state
#   into the copy folder's state/NAME, or puts them back in libvirt's places.
#   The seventh, the exchange step (its name is host-networks.nix's
#   exchange's step), sends a file from a VM's Outbox to another VM's Inbox
#   or to the host's inbox through broker-vm, lists a VM's Outbox, shows
#   broker-vm's log, cleans a VM's kept copies and reads their figures.
# The networks section's path check reads, as the user, the two answer
# points inside the service VMs: firewall-check (gateway.nix) and wifi-check
# (net.nix), over vsock with socat.
{ config, lib, pkgs, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  st = import ../isolation/stations.nix;
  ul = import ../isolation/uplinks.nix;
  firewallVm = hostNetworks.vms.firewall-vm;
  firewallConfig = config.microvm.vms.${firewallVm}.config.config;
  brokerVm = hostNetworks.vms.broker-vm;
  brokerConfig = config.microvm.vms.${brokerVm}.config.config;
  exchange = hostNetworks.exchange;
  libvirtPackage = config.virtualisation.libvirtd.package;
  qemuPackage = config.virtualisation.libvirtd.qemu.package;
  uri = "qemu:///system";
  # The command's name, written only here: the command on the host, the
  # store names of the settings and the program, and the name the program
  # prints (handed over in the settings as command).
  command = "bastion";

  # libvirt's folders: the nixpkgs build's local state folder is /var, and
  # libvirt keeps its state in lib/libvirt under it: the definitions' firmware
  # variables in qemu/nvram, the TPM state in swtpm, one folder per VM's UUID.
  libvirtDir = "/var/lib/libvirt";
  nvramDir = "${libvirtDir}/qemu/nvram";
  swtpmDir = "${libvirtDir}/swtpm";
  # The user libvirt runs swtpm as, and its group: tss when a user and a
  # group of that name exist, else root (libvirt v12.2.0
  # src/qemu/qemu_conf.c 229-235); virtualization.nix makes both, and the
  # host's qemu.conf names no swtpm_user (looking-glass.nix).
  swtpmUser = "tss";

  # The owner: the one normal user of the host (users.nix); NixOS gives a
  # normal user the home /home/NAME and the group users (nixpkgs
  # nixos/modules/config/users-groups.nix 480-484). The copy folder in its
  # home, named after the command: each VM's definition and the copy of
  # networks.json, written by the program as the owner after every change,
  # and state/NAME, the firmware variables and TPM state state-copy copies,
  # readable by the owner alone.
  owner = lib.head (lib.attrNames (lib.filterAttrs (n: u: u.isNormalUser) config.users.users));
  copyDir = "${config.users.users.${owner}.home}/presets/${command}";
  # The disks (a btrfs subvolume, hosts/bastion/default.nix), the templates'
  # disks, and the folder of retired VMs, one folder per VM's name.
  images = "${libvirtDir}/images";
  templates = "${images}/templates";
  retired = "${images}/retired";
  virtioIso = "${images}/virtio-win-0.1.285-1.iso";
  # The virtio ISO's viosock folder alone: the vsock driver and vstbridge.exe
  # in one folder per Windows version, extracted with libarchive's bsdtar as
  # nixpkgs extracts the whole ISO (nixpkgs pkgs/by-name/vi/virtio-win/
  # package.nix 17-21); a folder named on bsdtar's command line takes all
  # below it (libarchive v3.8.9 libarchive/archive_match.c 241 and 831-834).
  # The ISO's other folders are not copied into the store again. The
  # program's exchange-files copies it whole for the presets module of the
  # exchange.
  viosock = pkgs.runCommand "${pkgs.virtio-win.name}-viosock" { nativeBuildInputs = [ pkgs.libarchive ]; } ''
    mkdir -p $out
    bsdtar -xf ${pkgs.virtio-win.src} -C $out viosock
  '';
  # The driver folders for the devices of the program's VMs (bastion.py's
  # domain_xml), from the extracted virtio-win tree nixpkgs builds, its
  # output the ISO's root (nixpkgs pkgs/by-name/vi/virtio-win/package.nix
  # 21 and 26-27); each folder's name and its w10/amd64 and w11/amd64
  # subfolders as the ISO's own file listing names them: viostor for the
  # disk on bus virtio, NetKVM for the network card of model virtio, qxldod
  # for the video of model qxl, which the ISO holds for w10 alone. The
  # program's virtio-files copies it whole for the presets module repair.
  virtioDrivers = pkgs.runCommand "${pkgs.virtio-win.name}-drivers" { } ''
    for d in viostor/w10/amd64 viostor/w11/amd64 NetKVM/w10/amd64 NetKVM/w11/amd64 qxldod/w10/amd64; do
      mkdir -p "$out/$d"
      cp -R ${pkgs.virtio-win}/"$d"/. "$out/$d/"
    done
  '';

  # The templates. disk: GiB, the size of the template's empty disk, also the
  # smallest disk a VM made from it gets; memory: MiB; download: a word of
  # the Windows .iso's name in ~/Downloads, for bastion template.
  templateList = [
    { t = "win10"; iso = "${images}/win10-ltsc.iso"; download = "windows_10"; disk = 40;
      memory = 8192; vcpus = 4; win11 = false;
      uuid = "b684b246-050c-4baa-bb3b-66135b30aec5"; }
    { t = "win11"; iso = "${images}/win11.iso"; download = "windows_11"; disk = 64;
      memory = 8192; vcpus = 4; win11 = true;
      uuid = "d5ad5f98-692b-44fc-85e7-094a7694296e"; }
  ];
  # Each template's domain, disk and sealed mark (template-seal makes the mark).
  tpls = map (p: p // {
    name = "tpl-${p.t}";
    file = "${templates}/${p.t}.qcow2";
    sealed = "${templates}/${p.t}.sealed";
  }) templateList;

  # What always stays for the host itself: threads, RAM (GiB), disk (GiB).
  share = { threads = 4; ram = 4; disk = 50; };
  # The steps of the pick lists: RAM in 1 GiB, a disk in 10 GiB.
  steps = { ram = 1; disk = 10; };

  # The service VMs of host-networks.nix, counted in every start's sum: their
  # threads and RAM from their own modules, their unit, and what it means
  # when one stops (host-networks.nix).
  services = lib.mapAttrsToList (k: v: {
    name = v;
    vcpu = config.microvm.vms.${v}.config.config.microvm.vcpu;
    mem = config.microvm.vms.${v}.config.config.microvm.mem;
    unit = "microvm@${v}.service";
    meaning = hostNetworks.meanings.${k};
  }) hostNetworks.vms;

  # The host: the one station of stations.nix without a MAC; its address is
  # never given to a VM, nor the first address of a network's range (the
  # firewall VM's on that network, which the program derives from the range).
  hostPort = lib.head (lib.attrNames (lib.filterAttrs (n: s: !(s ? mac)) st));
  # The names a new network may not take, since its name is also the firewall
  # VM's leg on it: the switches, the service VMs and their cables.
  hostNetworkNames = lib.attrValues hostNetworks.switches
    ++ lib.attrValues hostNetworks.vms
    ++ map (c: c.name) (lib.attrValues hostNetworks.cables);
  # The names a new VM's cable may not take: the switches, the service
  # cables, the host's cable, the uplinks' devices, the service VMs.
  namesInUse = lib.attrValues hostNetworks.switches
    ++ map (c: c.name) (lib.attrValues hostNetworks.cables)
    ++ [ hostPort ]
    ++ map (u: u.device) (lib.attrValues ul.uplinks)
    ++ lib.attrValues hostNetworks.vms;
  # A VM's name is its cable's name: the longest network device name the
  # kernel takes is IFNAMSIZ (16) less its end byte.
  ifnamsiz = 16;

  # firewall-apply over vsock: firewall-vm's number and the port its socket
  # listens on, from that VM's own module.
  applyCid = toString firewallConfig.microvm.vsock.cid;
  applyPort = lib.last (lib.splitString ":" (lib.head firewallConfig.systemd.sockets.firewall-apply.listenStreams));
  networksFile = hostNetworks."networks.json";

  # The first vsock number of the VMs the program starts: at each start it
  # gives the VM, for that start only, the lowest number from this one up
  # that no running VM holds (bastion.py's start_plan and set_vsock); every
  # service VM's number, read from its own module, lies below it (the
  # assertion at the end of this file).
  vsockFirst = 100;

  # The key of a station's list of destinations in networks.json
  # (host-networks.nix's exchange), as a jq string.
  sendsTo = builtins.toJSON hostNetworks.exchange.sends-to;

  # What networks-apply and firewall-apply refuse in networks.json, the same
  # checks as theirs, a station's resolution (the screen size its Windows is
  # locked at, which only the program reads) that is not WIDTHxHEIGHT, and a
  # station's list of destinations (which broker-vm reads, broker.nix) that
  # is there and not a list of names; true when the file holds what all of
  # them read.
  networksCheck = ''
    if (.networks | type) != "object" then error("networks is not a set of networks")
    elif (.stations | type) != "object" then error("stations is not a set of stations")
    else . end
    | .networks as $nets
    | (.networks | to_entries[] | .key as $n | .value
      | if (."ip-range" | type) != "string" or (."ip-range" | test("^[0-9]{1,3}([.][0-9]{1,3}){3}/[0-9]{1,2}$") | not)
        then error("network \($n): ip-range \(."ip-range") is not an IPv4 range")
        elif (.lane | type) != "number" or .lane != (.lane | trunc) or .lane < 1 or .lane > 4094
        then error("network \($n): lane \(.lane) is not a whole number from 1 to 4094")
        elif (."reach-each-other" | type) != "boolean"
        then error("network \($n): reach-each-other is not true or false")
        else empty end),
      (.stations | to_entries[] | .key as $n | .value
      | if (.network | type) != "string" or $nets[.network] == null then error("station \($n): its network is not in networks")
        elif (.mac | type) != "string" or (.mac | test("^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$") | not) then error("station \($n): mac is not a MAC")
        elif (.ip | type) != "string" or (.ip | test("^[0-9]{1,3}([.][0-9]{1,3}){3}$") | not) then error("station \($n): ip is not an IPv4 address")
        elif ([.rule] | inside(["open", "listed", "none"]) | not) then error("station \($n): rule is not open, listed or none")
        elif (.names // [] | type) != "array" or ((.names // []) | map(type == "string" and test("^[A-Za-z0-9.-]+$")) | all | not) then error("station \($n): names is not a list of names")
        elif has("resolution") and ((.resolution | type) != "string" or (.resolution | test("^[0-9]+x[0-9]+$") | not)) then error("station \($n): resolution is not WIDTHxHEIGHT")
        elif has(${sendsTo}) and ((.[${sendsTo}] | type) != "array" or (.[${sendsTo}] | map(type == "string") | all | not)) then error("station \($n): \(${sendsTo}) is not a list of names")
        else empty end),
      true
  '';

  # networks-write: the new networks.json on standard input, refused whole
  # when it does not hold what networks-apply and firewall-apply read; else
  # written in place in one move, then networks-apply loads the guard from
  # it and firewall-apply, reached over vsock, the rules, the listed sets
  # and the DHCP hosts. It waits up to internet-wait seconds
  # (host-networks.nix) for firewall-apply's answer.
  networksWrite = pkgs.writeShellScript "networks-write" ''
    export PATH=${lib.makeBinPath [ pkgs.jq pkgs.socat pkgs.coreutils config.systemd.package ]}
    set -u
    file=${networksFile}
    new=$(cat)
    if ! printf '%s' "$new" | jq -e ${lib.escapeShellArg networksCheck} >/dev/null; then
      echo "networks-write: refused whole (the reason stands above); $file is unchanged."
      exit 1
    fi
    tmp=$(mktemp "$file.XXXXXX")
    printf '%s\n' "$new" > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$file"
    echo "$file is written."
    rc=0
    if systemctl restart networks-apply.service; then
      echo "networks-apply: the guard is loaded from it."
    else
      echo "networks-apply refused it; the guard loaded before stays."
      rc=1
    fi
    if answer=$(socat -t ${toString hostNetworks.internet-wait} - VSOCK-CONNECT:${applyCid}:${applyPort} </dev/null 2>&1) && [ -n "$answer" ]; then
      echo "${firewallVm}: $answer"
    else
      echo "firewall-apply did not load it''${answer:+ ($answer)}; ${firewallVm} keeps the rules it had (gate log shows why)."
      rc=1
    fi
    exit $rc
  '';

  # disk-grow NAME GIB: an off VM's disk grown to GIB GiB (the program offers
  # bigger sizes only); the VM sees it at its next start.
  diskGrow = pkgs.writeShellScript "disk-grow" ''
    export PATH=${lib.makeBinPath [ libvirtPackage qemuPackage pkgs.coreutils pkgs.gawk ]}
    set -eu
    file=$(virsh --connect ${uri} domblklist "$1" --details | awk '$2 == "disk" { print $4; exit }')
    qemu-img resize "$file" "$2"G >/dev/null
    echo "$1's disk is $2 GB now; Windows sees it at the VM's next start, and the presets script 70-grow-c extends C:."
  '';

  # disk-retire NAME: the folder retired/NAME made (an existing one refuses
  # it), the VM's definition written into it, and its disks, its firmware
  # variables and its TPM state moved into it. Nothing is deleted; the
  # program then undefines the VM keeping both.
  diskRetire = pkgs.writeShellScript "disk-retire" ''
    export PATH=${lib.makeBinPath [ libvirtPackage pkgs.coreutils pkgs.gawk pkgs.gnused ]}
    set -eu
    name=$1
    V="virsh --connect ${uri}"
    dir=${retired}/$name
    xml=$($V dumpxml --inactive "$name")
    uuid=$($V domuuid "$name")
    disks=$($V domblklist "$name" --details | awk '$2 == "disk" { print $4 }')
    install -d -m 0755 ${retired}
    mkdir -m 0755 "$dir"
    printf '%s\n' "$xml" > "$dir/$name.xml"
    echo "$name's definition is in $dir/$name.xml."
    for f in $disks; do
      mv "$f" "$dir/"
      echo "$f is in $dir now."
    done
    nvram=$(printf '%s\n' "$xml" | sed -n 's|.*<nvram[^>]*>\(.*\)</nvram>.*|\1|p')
    for f in $nvram ${nvramDir}/"$name"_VARS*; do
      if [ -e "$f" ]; then
        mv "$f" "$dir/"
        echo "$f is in $dir now."
      fi
    done
    if [ -e ${swtpmDir}/"$uuid" ]; then
      mv ${swtpmDir}/"$uuid" "$dir/tpm"
      echo "its TPM state is in $dir/tpm now."
    fi
  '';

  # make-disk TEMPLATE: the template's empty disk, and the virtio ISO copied
  # once. make-disk TEMPLATE ISO: first ISO, the template's Windows .iso as
  # downloaded (bastion gives it only while the .iso is not in place), copied
  # in place, the two compared by their sha256 and a differing copy
  # removed; then the same. make-disk TEMPLATE NAME GIB: an independent copy
  # of the sealed template as NAME's disk, grown to GIB GiB (Windows extends
  # C: by itself, the presets script 70-grow-c); it appears under its name
  # only when complete, and never in place of a disk that is there.
  makeDisk = pkgs.writeShellScript "make-disk" ''
    export PATH=${lib.makeBinPath [ qemuPackage pkgs.coreutils ]}
    set -eu
    t=$1
    case "$t" in
    ${lib.concatMapStrings (p: "${p.t}) size=${toString p.disk}; iso=${p.iso} ;;\n    ") templateList}*) echo "make-disk: no template $t."; exit 1 ;;
    esac
    if [ $# -le 2 ]; then
      if [ $# = 2 ]; then
        install -m 0644 "$2" "$iso" || { echo "make-disk: the copy failed."; exit 1; }
        if [ "$(sha256sum < "$2")" != "$(sha256sum < "$iso")" ]; then
          rm -f "$iso"
          echo "make-disk: the copy differs from the download."
          exit 1
        fi
      fi
      install -d -m 0755 ${templates}
      if [ ! -e ${virtioIso} ]; then
        install -m 0644 ${pkgs.virtio-win.src} ${virtioIso}
      fi
      if [ ! -e ${templates}/"$t".qcow2 ]; then
        qemu-img create -f qcow2 ${templates}/"$t".qcow2 "$size"G
      fi
      exit 0
    fi
    name=$2; size=$3
    dst=${images}/$name.qcow2
    if [ -e "$dst" ]; then
      echo "make-disk: $dst is there; nothing changed."
      exit 1
    fi
    making=$dst.making
    trap 'rm -f "$making"' EXIT
    qemu-img convert -f qcow2 -O qcow2 ${templates}/"$t".qcow2 "$making"
    qemu-img resize "$making" "$size"G >/dev/null
    mv "$making" "$dst"
    echo "$dst is made from $t, $size GB."
  '';

  # template-seal TEMPLATE: the template's sealed mark written (bastion seal
  # runs it after its checks); a name that is not a template's is refused.
  templateSeal = pkgs.writeShellScript "template-seal" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    set -eu
    t=$1
    case "$t" in
    ${lib.concatMapStrings (p: "${p.t}) sealed=${p.sealed} ;;\n    ") tpls}*) echo "template-seal: no template $t."; exit 1 ;;
    esac
    touch "$sealed"
  '';

  # state-copy save NAME UUID: NAME's firmware variables, the nvram file
  # libvirt names NAME_VARS and its format's extension (libvirt v12.2.0
  # src/qemu/qemu_firmware.c 1059-1068), and the TPM state of the UUID, the
  # folder swtpmDir/UUID (src/qemu/qemu_tpm.c 57-76), copied under their own
  # names into the copy folder's state/NAME, owned by the owner, folders 0700
  # and files 0600; the copy folder must be there (the program makes it).
  # state-copy restore NAME UUID: the two put back in libvirt's places with
  # libvirt's owners and modes: the nvram file 0600 with the owner and group
  # of nvramDir, which libvirt gives its QEMU user and group at every start
  # of the daemon, the pair it makes the file with (src/qemu/qemu_driver.c
  # 737 and 789-795, src/qemu/qemu_process.c 4954-4956); the UUID folder 0711
  # as root, every folder below it 0700 and every file 0600, owned by
  # swtpmUser (src/qemu/qemu_tpm.c 181-213 and 696). It refuses, changing
  # nothing, when state/NAME holds no firmware variables of NAME, or when the
  # nvram file or the UUID folder is there already. Both refuse a NAME that
  # is not one entry of a folder (empty, ".", "..", a "/" in it) or holds a
  # newline (libvirt refuses that name, src/qemu/qemu_driver.c 6507), and a
  # UUID not in the form libvirt writes it (src/util/viruuid.c 146-156).
  stateCopy = pkgs.writeShellScript "state-copy" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    set -eu
    if [ $# -ne 3 ]; then
      echo "state-copy: save or restore, the name and the UUID."
      exit 1
    fi
    way=$1; name=$2; uuid=$3
    case "$name" in
    ""|.|..|*/*|*"
    "*) echo "state-copy: refused, the name $name is not one entry of a folder."; exit 1 ;;
    esac
    case "$uuid" in
    ${lib.concatStringsSep "-" (map (n: lib.concatStrings (lib.replicate n "[0123456789abcdef]")) [ 8 4 4 4 12 ])}) ;;
    *) echo "state-copy: refused, $uuid is not a UUID as libvirt writes it."; exit 1 ;;
    esac
    if [ ! -d "${copyDir}" ]; then
      echo "state-copy: ${copyDir} is not there."
      exit 1
    fi
    state=${copyDir}/state/$name
    case "$way" in
    save)
      found=
      for f in ${nvramDir}/"$name"_VARS.*; do
        if [ -e "$f" ]; then
          found=1
        fi
      done
      if [ -z "$found" ]; then
        echo "state-copy: $name has no firmware variables in ${nvramDir} yet, it has never started."
        exit 1
      fi
      install -d -m 0700 -o ${owner} -g ${config.users.users.${owner}.group} "${copyDir}/state"
      install -d -m 0700 -o ${owner} -g ${config.users.users.${owner}.group} "$state"
      for f in ${nvramDir}/"$name"_VARS.*; do
        if [ -e "$f" ]; then
          install -m 0600 -o ${owner} -g ${config.users.users.${owner}.group} "$f" "$state/"
        fi
      done
      echo "$name's firmware variables are in $state."
      if [ -d ${swtpmDir}/"$uuid" ]; then
        install -d -m 0700 -o ${owner} -g ${config.users.users.${owner}.group} "$state/$uuid"
        cp -R ${swtpmDir}/"$uuid"/. "$state/$uuid/"
        chown -R ${owner}:${config.users.users.${owner}.group} "$state/$uuid"
        chmod -R u=rwX,go= "$state/$uuid"
        echo "$name's TPM state is in $state/$uuid."
      fi
      ;;
    restore)
      found=
      for f in "$state/$name"_VARS.*; do
        if [ -e "$f" ]; then
          found=1
        fi
      done
      if [ -z "$found" ]; then
        echo "state-copy: $state holds no firmware variables of $name, nothing changed."
        exit 1
      fi
      for f in ${nvramDir}/"$name"_VARS.*; do
        if [ -e "$f" ]; then
          echo "state-copy: $f is there already, nothing changed."
          exit 1
        fi
      done
      if [ -d "$state/$uuid" ] && [ -e ${swtpmDir}/"$uuid" ]; then
        echo "state-copy: ${swtpmDir}/$uuid is there already, nothing changed."
        exit 1
      fi
      for f in "$state/$name"_VARS.*; do
        if [ -e "$f" ]; then
          back=${nvramDir}/$(basename -- "$f")
          install -m 0600 "$f" "$back"
          chown --reference=${nvramDir} "$back"
        fi
      done
      echo "$name's firmware variables are back in ${nvramDir}."
      if [ -d "$state/$uuid" ]; then
        if [ ! -d ${swtpmDir} ]; then
          install -d -m 0711 ${swtpmDir}
        fi
        install -d -m 0711 ${swtpmDir}/"$uuid"
        cp -R "$state/$uuid"/. ${swtpmDir}/"$uuid"/
        for f in ${swtpmDir}/"$uuid"/*; do
          if [ -e "$f" ]; then
            chown -R ${swtpmUser}:${swtpmUser} "$f"
            chmod -R u=rwX,go= "$f"
          fi
        done
        echo "$name's TPM state is back in ${swtpmDir}/$uuid."
      fi
      ;;
    *)
      echo "state-copy: save or restore, not $way."
      exit 1
      ;;
    esac
  '';

  # The exchange step's paths, from host-networks.nix's exchange or derived
  # by one naming rule: the host's key for broker-vm,
  # named after it in the folder of the exchange key (broker.nix makes
  # both); each known-hosts file named after what it reaches, broker-vm or
  # the accounts of the exchange key, in that folder; the folder of a send
  # stopped after the take, inside staging; broker-vm's journal folder on
  # the host, as gate log reads firewall-vm's (host.nix): the journal
  # share's folder and the VM's machine id without its dashes.
  sshDir = dirOf exchange.key;
  brokerKey = "${sshDir}/${brokerVm}";
  brokerKnown = "${sshDir}/known_hosts_${brokerVm}";
  exchangeKnown = "${sshDir}/known_hosts_${baseNameOf exchange.key}";
  failedDir = "${exchange.staging}/${exchange.failed}";
  brokerJournal = "${config.microvm.stateDir}/${brokerVm}/journal/${lib.replaceStrings [ "-" ] [ "" ] brokerConfig.microvm.machineId}";
  # The lines the broker section's transfers shows: the last ones, as gate
  # log shows firewall-vm's (host.nix); the command shows all.
  transfersLines = 300;

  # The exchange step's words, each a shell variable named by its group and
  # its key in host-networks.nix's exchange, a dash in a key written as an
  # underscore: lines_not_running, log_from, reasons_hash, verbs_take and so
  # on.
  exchangeWords = lib.concatMapStrings (g: lib.concatStrings (lib.mapAttrsToList
    (k: v: "${g}_${lib.replaceStrings [ "-" ] [ "_" ] k}=${lib.escapeShellArg v}\n") exchange.${g}))
    [ "lines" "log" "reasons" "verbs" ];

  # The exchange step, run as root through sudo; its first argument is the
  # action, by host-networks.nix's words:
  #   send FROM FILE TO  one file from FROM's Outbox to TO's Inbox, or to the
  #     host's inbox when TO is the host's name, in this order: FROM and TO
  #     running VMs with a live vsock number, read with virsh (libvirt
  #     v12.2.0 docs/manpages/virsh.rst 2546-2553 and 3046-3075; --xpath
  #     prints each node of a node set on a line, tools/virsh-util.c
  #     487-511); broker-vm's ask, a refusal its REFUSED line; broker-vm's
  #     usage, the full line when the kept copies are at or past the limit;
  #     for a VM as TO, its sftp session opened and its Inbox listed, kept
  #     open for the put; the file taken through sftp into one staging
  #     file; its sha256; broker-vm's take with the file on standard input,
  #     a full refusal its full line, any other refusal broker-vm's own
  #     line; the two hashes compared; the delivery at the first free name:
  #     NAME, else "STEM (2)EXT", "STEM (3)EXT" and on, EXT from the last dot
  #     that is not the first character, compared without regard to case in
  #     a VM's Inbox and with case in the host's inbox; broker-vm's done;
  #     one journal line of this step. A hash difference or a failed
  #     delivery keeps the staging file, its name kept, under failed in the
  #     folder named after FROM, with a journal line; every other stop
  #     removes it; a delivered file's staging file is removed.
  #   OUTBOX FROM  (the word of the Outbox folder) the file names in FROM's
  #     Outbox, one per line.
  #   transfers LINES [NAME]  broker-vm's journal lines of its program, the
  #     last LINES of them, all when LINES is empty, all or those naming
  #     NAME as from or to (systemd v260.5 man/journalctl.xml 153, 390,
  #     446-466, 681-682).
  #   clean NAME  broker-vm's clean of NAME, its answer printed as the
  #     cleaned line, a refusal as broker-vm's own line; then the files of
  #     NAME's stopped sends under failed, each logged, then deleted, and
  #     the failed-cleaned line when at least one was; nothing on the host
  #     when NAME holds a slash or is . or ..; 1 when broker-vm's clean
  #     failed.
  #   usage  broker-vm's usage line, "USED, SIZE, LIMIT" in bytes.
  # ssh's options on its command line, which it reads first (OpenSSH
  # V_10_5_P1 ssh_config.5 50, 70), past the system's settings for vsock
  # hosts (systemd v260.5 src/ssh-generator/20-systemd-ssh-proxy.conf.in
  # 12-20): for broker-vm, as root, its key, its known-hosts file,
  # StrictHostKeyChecking accept-new while that file is empty, the
  # fingerprint then printed once, yes after; for a VM, the exchange key,
  # User the account, HostKeyAlias its name, accept-new and the exchange's
  # known-hosts file; BatchMode on both (ssh_config.5 363, 1129, 1147, 1200,
  # 2037-2062, 2189, 2203; ssh.1 296, 505, 1580; sftp.1 125-150, 188, 212;
  # sftp sets BatchMode itself with -b, sftp.c 2550-2556).
  exchangeStep = pkgs.writeShellScript exchange.step ''
    export PATH=${lib.makeBinPath [ libvirtPackage config.programs.ssh.package pkgs.coreutils pkgs.util-linux config.systemd.package ]}
    # Names in UTF-8 as they are: sftp prints a byte that is no character of
    # its locale escaped (OpenSSH V_10_5_P1 utf8.c 130-175, 326-356).
    export LC_ALL=C.UTF-8
    set -u
    uri=${uri}
    broker=${lib.escapeShellArg brokerVm}
    cid=${toString brokerConfig.microvm.vsock.cid}
    host=${lib.escapeShellArg hostPort}
    key=${lib.escapeShellArg brokerKey}
    known=${lib.escapeShellArg brokerKnown}
    xkey=${lib.escapeShellArg exchange.key}
    xknown=${lib.escapeShellArg exchangeKnown}
    journal=${lib.escapeShellArg brokerJournal}
    staging=${lib.escapeShellArg exchange.staging}
    inbox=${lib.escapeShellArg exchange.inbox}
    failed=${lib.escapeShellArg failedDir}
    account=${lib.escapeShellArg exchange.account}
    folder=${lib.escapeShellArg exchange.folder}
    infolder=${lib.escapeShellArg exchange.inbox-folder}
    outfolder=${lib.escapeShellArg exchange.outbox-folder}
    module=${lib.escapeShellArg exchange.module}
    command=${lib.escapeShellArg command}
    step=${lib.escapeShellArg exchange.step}
    send=${lib.escapeShellArg exchange.send}
    transfers=${lib.escapeShellArg exchange.transfers}
    clean=${lib.escapeShellArg exchange.clean}
    ${exchangeWords}
    nl='
    '
    # fill FORMAT NAME=VALUE ...: FORMAT with each {NAME} replaced by its
    # VALUE, printed.
    fill() {
      f=$1
      shift
      for a in "$@"; do
        f=''${f//"{''${a%%=*}}"/"''${a#*=}"}
      done
      printf '%s\n' "$f"
    }
    # note EVENT FROM TO NAME BYTES SHA256 REASON: the line of the parts
    # given (an empty one is left out) into the journal under this step's
    # name, in the form and the words of broker-vm's lines (broker.nix); it
    # stays in l.
    note() {
      l=$1
      if [ -n "$2" ]; then l="$l, $log_from $2"; fi
      if [ -n "$3" ]; then l="$l, $log_to $3"; fi
      if [ -n "$4" ]; then l="$l, $log_name $4"; fi
      if [ -n "$5" ]; then l="$l, $log_bytes $5"; fi
      if [ -n "$6" ]; then l="$l, $log_sha256 $6"; fi
      if [ -n "$7" ]; then l="$l, $log_reason $7"; fi
      logger -t "$step" -- "$l"
    }
    # gb BYTES: GB (GiB) with one decimal, rounded.
    gb() {
      g=$((1 << 30))
      t=$((($1 * 10 + g / 2) / g))
      printf '%s.%s GB' $((t / 10)) $((t % 10))
    }
    # broker COMMAND ...: broker-vm's program with COMMAND, over vsock, as
    # root with the key named after it; standard input is the caller's.
    broker() {
      if [ -s "$known" ]; then strict=yes; else strict=accept-new; fi
      ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile="$known" \
        -o StrictHostKeyChecking="$strict" "root@vsock/$cid" "$*"
      r=$?
      if [ "$strict" = accept-new ] && [ -s "$known" ]; then
        ssh-keygen -l -f "$known" >&2
      fi
      return $r
    }
    # vm NAME CID: sftp in batch mode, its commands on standard input, as the
    # exchange account at the VM's vsock number, with the exchange key; the
    # VM's host key under its name in the exchange's known-hosts file,
    # accepted when new.
    vm() {
      sftp -b - -i "$xkey" -o IdentitiesOnly=yes -o User="$account" -o HostKeyAlias="$1" \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$xknown" "vsock/$2"
    }
    # word PATH [pattern]: PATH as sftp's command line reads it back
    # (sftp.1 383-386, sftp.c 1198-1300): a backslash before each space,
    # tab, quote and #, which sftp drops; with pattern, for a path sftp
    # matches as a pattern (the get's source, the listing's folder, the
    # put's source), also a backslash before each glob character and
    # backslash, which the match undoes (sftp.c 1278-1290; the get's and
    # the put's destinations are not matched, 637-691, 726-791).
    word() {
      p=$1 o=
      while [ -n "$p" ]; do
        c=''${p:0:1}
        p=''${p:1}
        case "$c" in
        ' ' | $'\t' | '"' | "'" | '#') o="$o\\$c" ;;
        '*' | '?' | '[' | '\') if [ "''${2:-}" = pattern ]; then o="$o\\$c"; else o="$o$c"; fi ;;
        *) o="$o$c" ;;
        esac
      done
      printf '%s' "$o"
    }
    # re TEXT: TEXT for journalctl's pattern, a backslash before each
    # character that is no letter or digit, which then stands for itself.
    re() {
      p=$1 o=
      while [ -n "$p" ]; do
        c=''${p:0:1}
        p=''${p:1}
        case "$c" in
        [A-Za-z0-9]) o="$o$c" ;;
        *) o="$o\\$c" ;;
        esac
      done
      printf '%s' "$o"
    }
    # live NAME: c, NAME's vsock number from its live definition; the
    # not-running line and 1 when it does not run (virsh's word running,
    # tools/virsh-domain-monitor.c 130-147), the outside line and 1 when it
    # runs without one.
    live() {
      c=
      if [ "$(virsh --connect "$uri" domstate "$1" 2>/dev/null)" != running ]; then
        fill "$lines_not_running" vm="$1" command="$command"
        return 1
      fi
      x=$(virsh --connect "$uri" dumpxml "$1" --xpath //devices/vsock/cid 2>/dev/null)
      address="address=[\"']([0-9]+)"
      if [[ $x =~ $address ]]; then c=''${BASH_REMATCH[1]}; fi
      if [ -z "$c" ]; then
        fill "$lines_outside" vm="$1" command="$command"
        return 1
      fi
    }
    # space: used, size and limit, broker-vm's usage in bytes; its answer
    # printed and 1 when it gives none.
    space() {
      u=$(broker "$verbs_usage" </dev/null)
      r=$?
      if [ $r != 0 ]; then
        if [ -n "$u" ]; then printf '%s\n' "$u"; fi
        return 1
      fi
      used=''${u%%, *}
      u=''${u#*, }
      size=''${u%%, *}
      limit=''${u#*, }
    }
    # full: the full line, the limit's share of the size in whole percent.
    full() {
      fill "$lines_full" percent=$(((limit * 100 + size / 2) / size)) broker="$broker" \
        size="$(gb "$size")" command="$command" clean="$clean"
    }
    # refused ANSWER: broker-vm's refusal as the REFUSED line, its reason
    # the part after its last reason word; any other answer as it came.
    refused() {
      case "$1" in
      "$log_refused"*", $log_reason "*)
        fill "$lines_refused" from="$from" to="$to" reason="''${1##*, "$log_reason" }"
        ;;
      *)
        if [ -n "$1" ]; then printf '%s\n' "$1"; fi
        ;;
      esac
    }
    # free NAME CASE LIST: got, the first free name for NAME among LIST's
    # names, one per line, compared with case when CASE is case, else
    # without.
    free() {
      stem=$1 ext= i=1
      if [[ ''${1:1} == *.* ]]; then
        ext=.''${1##*.}
        stem=''${1%.*}
      fi
      got=$1
      while taken "$got" "$2" "$3"; do
        i=$((i + 1))
        got="$stem ($i)$ext"
      done
    }
    taken() {
      while IFS= read -r t; do
        if [ "$2" = case ]; then
          if [ "$t" = "$1" ]; then return 0; fi
        elif [ "''${t,,}" = "''${1,,}" ]; then
          return 0
        fi
      done <<< "$3"
      return 1
    }
    # open: TO's sftp session started and its Inbox listed into names,
    # the listing ended by lpwd's echo (sftp echoes each command it reads,
    # sftp.c 1579, its lines unbuffered past the line, 2310-2311), its own
    # line read too; the session stays open for the put. 1 when it failed,
    # with no-answer's line when no connection was made (no echo came).
    open() {
      coproc S { vm "$to" "$tocid"; }
      pid=$S_PID
      tx=''${S[1]} rx=''${S[0]}
      printf 'ls -1a %s\nlpwd\n' "$(word "/$infolder" pattern)" >&"$tx"
      names= seen= line=
      while IFS= read -r line <&"$rx"; do
        seen=1
        case "$line" in
        "sftp> lpwd") break ;;
        "/$infolder/"*) names="$names''${line#"/$infolder/"}$nl" ;;
        esac
      done
      if [ "$line" != "sftp> lpwd" ]; then
        exec {tx}>&-
        wait "$pid"
        if [ -z "$seen" ]; then fill "$lines_no_answer" vm="$to" module="$module"; fi
        return 1
      fi
      IFS= read -r line <&"$rx"
    }
    # shut: TO's session ended, its last lines read; its exit status.
    shut() {
      exec {tx}>&-
      while IFS= read -r line <&"$rx"; do :; done
      wait "$pid"
    }
    # stop REASON: the staging file kept under failed in the folder named
    # after FROM (made root 0700 when missing), its name kept; the stop
    # logged and printed in the form of broker-vm's refusals.
    stop() {
      install -d -m 0700 "$failed" "$failed/$from"
      mv "$sf" "$failed/$from/"
      note "$log_refused" "$from" "$to" "$file" "$bytes" "$sum" "$1"
      printf '%s\n' "$l"
    }
    send_file() {
      from=$1 file=$2 to=$3
      if [ "$from" != "$host" ]; then
        live "$from" || return 1
        fromcid=$c
      fi
      if [ "$to" != "$host" ]; then
        live "$to" || return 1
        tocid=$c
      fi
      b64=$(printf '%s' "$file" | base64 -w 0)
      answer=$(broker "$verbs_ask" "$from" "$to" "$b64" </dev/null)
      if [ $? != 0 ]; then
        refused "$answer"
        return 1
      fi
      fill "$lines_may" broker="$broker" from="$from" to="$to"
      space || return 1
      if [ "$used" -ge "$limit" ]; then
        full
        return 1
      fi
      if [ "$to" != "$host" ]; then
        open || return 1
      fi
      sf=$(mktemp "$staging/XXXXXXXX") || return 1
      said=$(printf 'get %s %s\n' "$(word "/$outfolder/$file" pattern)" "$(word "$sf")" | vm "$from" "$fromcid")
      if [ $? != 0 ]; then
        rm -f "$sf"
        if [ -z "$said" ]; then fill "$lines_no_answer" vm="$from" module="$module"; fi
        if [ "$to" != "$host" ]; then shut; fi
        return 1
      fi
      bytes=$(wc -c < "$sf")
      sum=$(sha256sum < "$sf")
      sum=''${sum%% *}
      answer=$(broker "$verbs_take" "$from" "$to" "$b64" "$bytes" < "$sf")
      if [ $? != 0 ]; then
        rm -f "$sf"
        case "$answer" in
        "$log_refused"*", $log_reason $reasons_full") full ;;
        *) if [ -n "$answer" ]; then printf '%s\n' "$answer"; fi ;;
        esac
        if [ "$to" != "$host" ]; then shut; fi
        return 1
      fi
      kept=''${answer#*, }
      ksum=''${kept%%, *}
      kept=''${kept#*, }
      if [ "$ksum" != "$sum" ]; then
        if [ "$to" != "$host" ]; then shut; fi
        stop "$reasons_hash"
        return 1
      fi
      fill "$lines_taken" from="$from" file="$file" bytes="$bytes" sha256="$sum"
      fill "$lines_kept" broker="$broker" kept="$kept"
      if [ "$to" = "$host" ]; then
        free "$file" case "$(ls -A "$inbox")"
        if ! install -m 0600 "$sf" "$inbox/$got"; then
          stop "$reasons_delivery"
          return 1
        fi
        path=$inbox/$got
      else
        free "$file" nocase "$names"
        printf 'put %s %s\n' "$(word "$sf" pattern)" "$(word "/$infolder/$got")" >&"$tx"
        if ! shut; then
          stop "$reasons_delivery"
          return 1
        fi
        path="$folder\\$infolder\\$got"
      fi
      answer=$(broker "$verbs_done" "$from" "$to" "$b64" "$(printf '%s' "$got" | base64 -w 0)" </dev/null)
      if [ $? != 0 ] && [ -n "$answer" ]; then printf '%s\n' "$answer"; fi
      note "$log_delivered" "$from" "$to" "$got" "$bytes" "$sum" ""
      fill "$lines_delivered" to="$to" path="$path"
      rm -f "$sf"
    }
    # outbox FROM: the file names in FROM's Outbox, one per line.
    outbox() {
      live "$1" || return 1
      listing=$(printf 'ls -1a %s\n' "$(word "/$outfolder" pattern)" | vm "$1" "$c")
      r=$?
      if [ $r != 0 ] && [ -z "$listing" ]; then
        fill "$lines_no_answer" vm="$1" module="$module"
        return 1
      fi
      while IFS= read -r line; do
        case "$line" in
        "/$outfolder/." | "/$outfolder/..") ;;
        "/$outfolder/"*) printf '%s\n' "''${line#"/$outfolder/"}" ;;
        esac
      done <<< "$listing"
      return $r
    }
    # show LINES [NAME]: broker-vm's journal lines of its program.
    show() {
      a=(-D "$journal" -t "$broker" --no-pager)
      if [ -n "$1" ]; then a+=(-n "$1"); fi
      if [ $# -gt 1 ]; then
        a+=(-g ", ($(re "$log_from")|$(re "$log_to")) $(re "$2")(,|\$)" --case-sensitive=yes)
      fi
      journalctl "''${a[@]}"
    }
    # clean_vm NAME: broker-vm's clean of NAME, its answer "COUNT, BYTES"
    # printed as the cleaned line, a refusal as broker-vm's own line; then,
    # unless NAME holds a slash or is . or .., each file of NAME's stopped
    # sends under failed logged, then deleted, and the failed-cleaned line
    # when at least one was; 1 when broker-vm's clean failed, else 0.
    clean_vm() {
      answer=$(broker "$verbs_clean" "$1" </dev/null)
      r=$?
      if [ $r = 0 ]; then
        fill "$lines_cleaned" broker="$broker" vm="$1" count="''${answer%%, *}" bytes="''${answer#*, }"
      elif [ -n "$answer" ]; then
        printf '%s\n' "$answer"
      fi
      case "$1" in
      */* | . | ..) ;;
      *)
        count=0 total=0
        for f in "$failed/$1"/*; do
          if [ ! -f "$f" ]; then continue; fi
          n=$(wc -c < "$f")
          sum=$(sha256sum < "$f")
          note "$log_cleaned" "$1" "" "''${f##*/}" "$n" "''${sum%% *}" ""
          rm -f "$f"
          count=$((count + 1)) total=$((total + n))
        done
        if [ $count -gt 0 ]; then
          fill "$lines_failed_cleaned" vm="$1" count="$count" bytes="$total"
        fi
        ;;
      esac
      if [ $r != 0 ]; then return 1; fi
    }
    action=''${1:-}
    if [ $# -gt 0 ]; then shift; fi
    case "$action" in
    "$send") send_file "$1" "$2" "$3" ;;
    "$outfolder") outbox "$1" ;;
    "$transfers") show "$@" ;;
    "$clean") clean_vm "$1" ;;
    "$verbs_usage") broker "$verbs_usage" </dev/null ;;
    *) exit 1 ;;
    esac
  '';

  # The settings the program is handed: every name and value it uses that
  # is not read from the host or from libvirt.
  settings = pkgs.writeText "${command}.json" (builtins.toJSON {
    inherit uri images retired virtioIso share steps services networksFile namesInUse;
    inherit hostNetworkNames firewallVm command copyDir vsockFirst;
    templates = tpls;
    switch = hostNetworks.switches.workstations;
    hostAddress = st.${hostPort}.ip;
    # The host's station name: the broker section offers it as a
    # destination; the host only receives.
    inherit hostPort;
    # The exchange's words and paths (host-networks.nix): the broker
    # section's words, the key of a station's list of destinations,
    # exchange-files' command, folder and words file for the presets module,
    # and the commands, the step and the lines of the sends.
    exchange = hostNetworks.exchange;
    # The store folder of the viosock files, which exchange-files copies.
    viosock = "${viosock}";
    # The store folder of the virtio driver folders, which virtio-files
    # copies.
    virtioDrivers = "${virtioDrivers}";
    nameMax = ifnamsiz - 1;
    # libvirt's own prefixes for cables (docs/formatdomain.rst).
    refusedPrefixes = [ "vnet" "vif" "macvtap" "macvlan" ];
    # The host's own internet: the address gate checks and the seconds gate
    # waits for it (host-networks.nix).
    internet = hostNetworks.internet;
    internetTimeout = hostNetworks.internet-wait;
    # The host's uplinks, read as gate status reads them.
    uplinks = lib.mapAttrsToList (n: u: { name = n; inherit (u) device; }) ul.uplinks;
    inherit (ul) prefer;
    nmcli = "${config.networking.networkmanager.package}/bin/nmcli";
    ip = "${pkgs.iproute2}/bin/ip";
    # The path check of the networks section: the cables of host-networks.nix
    # with their switches; the gate word that opens wifi-vm's Wi-Fi screen
    # (the uplink through the VMs of uplinks.nix, as host.nix finds it); the
    # two answer points inside the service VMs, each by its VM's vsock number
    # and the port its socket listens on, from that VM's own module, reached
    # with socat as networks-write reaches firewall-apply.
    wifiVm = hostNetworks.vms.wifi-vm;
    # broker-vm's name, for the broker section's first line.
    inherit brokerVm;
    # The lines the broker section's transfers shows.
    inherit transfersLines;
    wifiUplink = lib.head (lib.attrNames (lib.filterAttrs (n: u: u.kind == "vm") ul.uplinks));
    cables = map (c: { inherit (c) name; switch = hostNetworks.switches.${c.switch}; })
      (lib.attrValues hostNetworks.cables);
    firewallCheck = {
      cid = firewallConfig.microvm.vsock.cid;
      port = lib.toInt (lib.last (lib.splitString ":" (lib.head firewallConfig.systemd.sockets.firewall-check.listenStreams)));
    };
    wifiCheck = {
      cid = config.microvm.vms.${hostNetworks.vms.wifi-vm}.config.config.microvm.vsock.cid;
      port = lib.toInt (lib.last (lib.splitString ":" (lib.head
        config.microvm.vms.${hostNetworks.vms.wifi-vm}.config.config.systemd.sockets.wifi-check.listenStreams)));
    };
    socat = "${pkgs.socat}/bin/socat";
    bridge = "${pkgs.iproute2}/bin/bridge";
    systemctl = "${config.systemd.package}/bin/systemctl";
    privileged = {
      networks-write = "${networksWrite}";
      disk-grow = "${diskGrow}";
      disk-retire = "${diskRetire}";
      make-disk = "${makeDisk}";
      template-seal = "${templateSeal}";
      state-copy = "${stateCopy}";
      ${exchange.step} = "${exchangeStep}";
    };
  });

  python = pkgs.python3.withPackages (ps: [ ps.libvirt ps.textual ]);
  program = pkgs.runCommand "${command}-program" { } ''
    install -D -m 0644 ${./bastion.py} $out/bastion.py
    install -D -m 0644 ${./guards.py} $out/guards.py
  '';
  bastion = pkgs.writeShellScriptBin command ''
    exec ${python}/bin/python3 ${program}/bastion.py ${settings} "$@"
  '';
in
{
  config.environment.systemPackages = [ bastion ];
  # The exchange's words as JSON, the one place a script outside the tool
  # reads them: presets/attach.sh takes exchange-files' word from it
  # (environment.etc's text, nixpkgs nixos/modules/system/etc/etc.nix 106-113,
  # 151).
  config.environment.etc."${command}/exchange.json".text = builtins.toJSON hostNetworks.exchange;
  config.assertions = map (v:
    let cid = config.microvm.vms.${v}.config.config.microvm.vsock.cid; in {
      assertion = cid < vsockFirst;
      message = "${v}'s vsock number ${toString cid} is not below vsockFirst ${toString vsockFirst} in bastion.nix, "
        + "the first number the ${command} tool gives the VMs it starts";
    }) (lib.attrValues hostNetworks.vms);
}
