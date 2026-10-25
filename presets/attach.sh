#!/usr/bin/env bash
# Bastion: build the PRESETS stick (FAT32) from ~/presets/win and plug it into a VM.
# Usage: attach.sh [NAME]   - with no NAME, pick from a numbered list.
set -u
V="virsh -c qemu:///system"
src=~/presets/win
s=~/presets/presets.img
img=/var/lib/libvirt/images/presets.img

[ -d "$src" ] || { echo "STOP: $src not found. Extract bastion-win.tar.gz into ~/presets first."; exit 1; }

name=${1:-}
if [ -z "$name" ]; then
  doms=$($V list --all --name 2>/dev/null | sed '/^$/d')
  [ -n "$doms" ] || { echo "STOP: no VMs are defined."; exit 1; }
  echo "Pick a workstation:"
  PS3="number> "
  select d in $doms; do [ -n "${d:-}" ] && { name=$d; break; }; echo "pick a number from the list"; done
fi
[ -n "$name" ] || { echo "STOP: no workstation chosen."; exit 1; }
[ "$($V domstate "$name" 2>/dev/null | head -n 1)" = running ] || { echo "STOP: $name is not running. Start it first (bastion start $name)."; exit 1; }

# the screen size the VM's Windows is locked at (WIDTHxHEIGHT), or follows, from bastion;
# it goes onto the stick as win/resolution.txt for the presets module 96-resolution
if ! res=$(bastion resolution "$name"); then
  echo "$res"
  echo "The stick has no resolution.txt: 96-resolution changes nothing."
  res=""
fi

# the files of the presets module that sets the exchange up in Windows, from bastion into a temporary
# folder: the command's word read by its key exchange-files from /etc/bastion/exchange.json (bastion.nix
# writes it from host-networks.nix); the folder's content goes onto the stick under win/
ex=$(mktemp -d)
vio=""
trap 'rm -rf -- "$ex" ${vio:+"$vio"}' EXIT
if ! word=$(nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#jq -c jq -er '.["exchange-files"] // error("no exchange-files")' /etc/bastion/exchange.json 2>&1); then
  printf '%s\n' "$word"
  echo "The key exchange-files of /etc/bastion/exchange.json could not be read (the line above): the stick is built without the files of that command."
  rm -rf -- "$ex"
  ex=""
elif ! got=$(bastion "$word" "$ex" 2>&1); then
  printf '%s\n' "$got"
  echo "The stick is built without the files of bastion $word (the line above)."
  rm -rf -- "$ex"
  ex=""
fi

# the virtio driver folders for the VM's devices, from bastion into a temporary folder, for the presets
# module repair (run.cmd repair); the folder's content, virtio/, goes onto the stick under win/
vio=$(mktemp -d)
if ! got=$(bastion virtio-files "$vio" 2>&1); then
  printf '%s\n' "$got"
  echo "The stick is built without the driver folders of bastion virtio-files (the line above)."
  rm -rf -- "$vio"
  vio=""
fi

# bring the installers listed in win/assets/installers.json to their vendors' current versions;
# a failed check or download keeps the file as it is and says so, and the stick is built with what is there
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#curl nixpkgs#jq nixpkgs#_7zz -c bash -c '
  set -u
  a="$1"; list="$1/installers.json"; t=""; tv=""; x=""
  clean() { [ -z "$t" ] || rm -f -- "$t"; [ -z "$tv" ] || rm -f -- "$tv"; [ -z "$x" ] || rm -rf -- "$x"; t=""; tv=""; x=""; }
  trap clean EXIT; trap "exit 1" INT TERM HUP
  n=$(jq -r ".installers | length" "$list" 2>&1) || { echo "No installer updated: $list could not be read ($n)."; exit 0; }
  mapfile -t lim < <(jq -r ".curl // {} | to_entries[] | \"--\" + .key, (.value | tostring)" "$list")
  fetch() { curl -fsS -L --proto =https --proto-redir =https "${lim[@]}" "$@" 2>&1; }
  field() { printf %s "$e" | jq -r --arg k "$1" ".[\$k] // empty"; }
  pick() { printf %s "$ans" | jq -r --arg v "$v" --arg url "$d" --argjson hardware "$hw" "$(field "$1")" 2>/dev/null | head -n 1; }
  miss() { clean; echo "$f not updated: $1."; }
  why() { local l; l=$(printf %s "$1" | head -n 1); [ -z "$l" ] || printf " (%s)" "$l"; }
  i=0
  while [ "$i" -lt "$n" ]; do
    e=$(jq -c ".installers[$i]" "$list"); i=$((i+1)); v=""; d=""; hw="[]"
    f=$(field file)
    hv=$(field hardware)
    if [ -n "$hv" ]; then
      hw=$(for p in /sys/bus/pci/devices/*; do echo $(cat "$p/vendor" "$p/class" "$p/device" "$p/subsystem_vendor" "$p/subsystem_device"); done | jq -cRn --argjson h "$hv" "[inputs | split(\" \") | map(ltrimstr(\"0x\") | ascii_upcase) | {vendor: .[0], class: .[1], device: .[2], subsystem_vendor: .[3], subsystem_device: .[4]} | select(.vendor == \$h.vendor and (.class | startswith(\$h.class))) | del(.class)]")
      [ "$hw" != "[]" ] || { miss "no device of $(printf %s "$hv" | jq -r "\"vendor \(.vendor) and class \(.class)\"") is on this host"; continue; }
    fi
    r=$(field request); [ -z "$r" ] || r=$(jq -nr --argjson hardware "$hw" "$r")
    u=$(field check)$r
    h=${u#https://}; h=${h%%/*}
    ans=$(fetch "$u") || { miss "the version check at $h failed ($(printf %s "$ans" | head -n 1))"; continue; }
    v=$(pick version); case $v in ""|null) miss "the answer from $h holds no version"; continue;; esac
    old=$(cat "$a/$f.version" 2>/dev/null)
    [ "$v" = "$old" ] && continue
    d=$(pick download); case $d in ""|null) miss "the answer from $h holds no download for $v"; continue;; esac
    echo "Downloading $f $v (recorded: ${old:-none}) ..."
    t=$(mktemp -p "$a") || { miss "no temporary file could be made in $a"; continue; }
    msg=$(fetch -o "$t" "$d") || { miss "the download of $v failed ($(printf %s "$msg" | head -n 1))"; continue; }
    alg=$(field algorithm)
    if [ -n "$alg" ]; then
      if [ -n "$(field hash)" ]; then want=$(pick hash)
      else
        s=$(pick sums); p=$(pick line)
        sums=$(fetch "$s") || { miss "the $alg list for $v could not be read ($(printf %s "$sums" | head -n 1))"; continue; }
        want=$(printf "%s\n" "$sums" | jq -Rr --arg p "$p" "select(endswith(\"  \" + \$p)) | split(\" \")[0]" | head -n 1)
      fi
      have=$("${alg}sum" "$t"); have=${have%% *}
      [ -n "$want" ] && [ "$want" = "$have" ] || { miss "the download of $v does not match the $alg its vendor publishes"; continue; }
    fi
    inf=$(field inf)
    if [ -n "$inf" ]; then
      x=$(mktemp -d -p "$a" 2>&1) || { msg=$x; x=""; miss "the files the package should list its devices in could not be read$(why "$msg")"; continue; }
      msg=$(7zz e -y -bso0 -bsp0 -o"$x" "$t" "$inf" 2>&1) && compgen -G "$x/*.inf" >/dev/null || { miss "the files the package should list its devices in could not be read$(why "$msg")"; continue; }
      ids=$(printf %s "$hw" | jq -r ".[] | \"PCI\\\\VEN_\(.vendor)&DEV_\(.device)&SUBSYS_\(.subsystem_device)\(.subsystem_vendor)\"")
      while IFS= read -r id; do grep -qiF -- "$id" "$x"/*.inf || { miss "the package does not list this host'\''s device $id"; continue 2; }; done <<< "$ids"
      rm -rf -- "$x"; x=""
    fi
    mv -f -- "$t" "$a/$f" || { miss "the download of $v could not be put in place"; continue; }
    t=""
    { tv=$(mktemp -p "$a") && printf "%s\n" "$v" > "$tv" && mv -f -- "$tv" "$a/$f.version" && tv=""; } || { clean; echo "$f is now $v, but $f.version could not be written."; }
  done
  exit 0
' bash "$src/assets" || echo "No installer updated: curl, jq and 7-Zip could not be taken from nixpkgs (lines above)."

# bring the Looking Glass host installer of the build looking-glass.nix pins, as /etc/looking-glass-host.json names it
# (build, url, sha256); a failure keeps the file as it is and says so, and the stick is built with what is there
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#curl nixpkgs#jq nixpkgs#_7zz -c bash -c '
  set -u
  a="$1"; f=looking-glass-host.exe; meta=/etc/looking-glass-host.json; t=""; x=""
  clean() { [ -z "$t" ] || rm -f -- "$t"; [ -z "$x" ] || rm -rf -- "$x"; t=""; x=""; }
  trap clean EXIT; trap "exit 1" INT TERM HUP
  why() { local l; l=$(printf %s "$1" | head -n 1); [ -z "$l" ] || printf " (%s)" "$l"; }
  v=$(jq -er "[.build, .url, .sha256] | map(strings) | select(length == 3) | .[]" "$meta" 2>&1) || { echo "$f not updated: $meta could not be read$(why "$v")."; exit 0; }
  mapfile -t k <<< "$v"; b=${k[0]}; url=${k[1]}; want=${k[2]}
  miss() { clean; echo "$f $b not updated: $1."; exit 0; }
  sum() { local h; h=$(sha256sum "$1" 2>/dev/null) && printf %s "${h%% *}"; }
  [ "$(sum "$a/$f")" = "$want" ] && exit 0
  mapfile -t lim < <(jq -r ".curl // {} | to_entries[] | \"--\" + .key, (.value | tostring)" "$a/installers.json" 2>/dev/null)
  echo "Downloading $f $b ..."
  t=$(mktemp -p "$a") || miss "no temporary file could be made in $a"
  msg=$(curl -fsS -L --proto =https --proto-redir =https "${lim[@]}" -o "$t" "$url" 2>&1) || miss "the download from $url failed$(why "$msg")"
  got=$t
  if [ "$(sum "$t")" != "$want" ]; then
    x=$(mktemp -d -p "$a") || miss "no temporary folder could be made in $a"
    msg=$(7zz e -y -bso0 -bsp0 -o"$x" "$t" 2>&1)
    got=$(compgen -G "$x/*.exe" | head -n 1); [ -n "$got" ] || miss "nothing could be taken out of the download from $url$(why "$msg")"
    [ "$(sum "$got")" = "$want" ] || miss "the installer from $url does not match the sha256 looking-glass.nix pins"
  fi
  mv -f -- "$got" "$a/$f" || miss "the installer could not be put in place"
  [ "$got" != "$t" ] || t=""
  exit 0
' bash "$src/assets" || echo "looking-glass-host.exe not updated: curl, jq and 7-Zip could not be taken from nixpkgs (lines above)."

# size the image to the contents of win/, of the exchange's folder and of the driver folders plus a margin,
# FAT32 with 512-byte clusters
need=$(du -sbc "$src" ${ex:+"$ex"} ${vio:+"$vio"} 2>/dev/null | tail -n 1 | cut -f1); [ -n "$need" ] || need=0
mb=$(( need/1048576 + 192 )); [ "$mb" -lt 64 ] && mb=64
echo "Building a ${mb} MiB FAT32 stick from $src ..."

$V detach-disk "$name" sdz --live >/dev/null 2>&1
rm -f "$s"; truncate -s "${mb}M" "$s"
echo "start=2048, type=c" | sfdisk -q "$s" || { echo "STOP: could not partition the stick image."; exit 1; }
blocks=$(( (mb-1)*1024 ))
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#dosfstools nixpkgs#mtools -c sh -c '
  img="$1"; src="$2"; blocks="$3"; res="$4"; ex="$5"; vio="$6"
  mkfs.vfat -F 32 -s 1 --offset=2048 -n PRESETS "$img" "$blocks" >/dev/null || exit 1
  mcopy -s -i "$img@@1M" "$src" :: || exit 1
  if [ -n "$res" ]; then printf "%s\n" "$res" | mcopy -i "$img@@1M" - ::/win/resolution.txt || exit 1; fi
  if [ -n "$ex" ]; then mcopy -s -i "$img@@1M" "$ex"/* ::/win/ || exit 1; fi
  if [ -n "$vio" ]; then mcopy -s -i "$img@@1M" "$vio"/* ::/win/ || exit 1; fi
' sh "$s" "$src" "$blocks" "$res" "$ex" "$vio" || { echo "STOP: could not make the stick image."; exit 1; }
sudo install -m 0644 "$s" "$img" || { echo "STOP: could not copy the image to the libvirt pool."; exit 1; }
cat > ~/presets/stick.xml <<XML
<disk type='file' device='disk'>
  <driver name='qemu' type='raw'/>
  <source file='$img'/>
  <target dev='sdz' bus='usb' removable='on'/>
  <readonly/>
</disk>
XML
$V attach-device "$name" ~/presets/stick.xml --live || { echo "STOP: could not plug the stick into $name (lines above)."; exit 1; }
echo "ALL OK. In $name open the PRESETS drive and run  win\\run.cmd  (it elevates itself)."
echo "When done: $V detach-disk $name sdz --live"
