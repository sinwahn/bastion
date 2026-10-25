#!/usr/bin/env bash
# sync.sh - makes /etc/nixos and ~/presets on the host Bastion equal to the
# other machine, or the other machine equal to the host. One tar file carries
# both: the nixos git repository as a git bundle, and the presets folder as
# a tar with a SHA-256 hash for every file.
#
#   bash sync.sh pack <out-dir>   on the machine whose state is copied
#   bash sync.sh unpack <tar>     on the machine that takes that state
#
# Each machine's settings are one line in sync.conf next to this script,
# chosen by plain `hostname`, cut at the first dot. README.txt has the steps.
#
# Test hook: when the variable HOSTNAME_OVERRIDE is set, its value is used
# in place of plain `hostname`, cut at the first dot, to choose the sync.conf line. It exists only for
# tests on one machine; normal use never sets it.

set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
CONF=$SRC/sync.conf
LOG=

out()   { if [ -n "$LOG" ]; then tee -a "$LOG"; else cat; fi; }
say()   { printf '%s\n' "$*" | out; }
stop()  { say "STOP: $*"; exit 1; }
usage() { printf '%s\n' "usage: sync.sh pack <out-dir>" "       sync.sh unpack <tar>" >&2; exit 1; }

# Commands on the nixos dir run as root when its sync.conf line says sudo=yes.
nrun() { if [ "$SUDO" = yes ]; then sudo "$@"; else "$@"; fi; }
ngit() { nrun git -C "$NIXOS" "$@"; }

# Sets HOST, NIXOS, PRESETS, SUDO and REBUILD from this host's sync.conf line.
pick_host() {
  if [ -n "${HOSTNAME_OVERRIDE+set}" ]; then
    HOST=$HOSTNAME_OVERRIDE
  else
    local h
    h=$(hostname) || stop "hostname failed."
    HOST=${h%%.*}
  fi
  [ -f "$CONF" ] || stop "no $CONF."
  local name rest found= kv key val
  local -a kvs
  while read -r name rest; do
    if [ "$name" = "$HOST" ]; then found=1; break; fi
  done < "$CONF"
  [ -n "$found" ] || stop "$CONF has no line for the host '$HOST'."
  NIXOS= PRESETS= SUDO= REBUILD=
  read -ra kvs <<< "$rest"
  for kv in "${kvs[@]}"; do
    key=${kv%%=*}; val=${kv#*=}
    case $val in "~"*) val=$HOME${val#"~"} ;; esac
    case $key in
      nixos) NIXOS=$val ;;
      presets) PRESETS=$val ;;
      sudo) SUDO=$val ;;
      rebuild) REBUILD=$val ;;
    esac
  done
  [ -n "$NIXOS" ] || stop "the sync.conf line for '$HOST' has no nixos=."
  [ -n "$PRESETS" ] || stop "the sync.conf line for '$HOST' has no presets=."
  [ -n "$REBUILD" ] || stop "the sync.conf line for '$HOST' has no rebuild=."
  case $SUDO in yes|no) ;; *) stop "the sync.conf line for '$HOST' needs sudo=yes or sudo=no." ;; esac
}

cmd_pack() {
  [ $# -eq 1 ] || usage
  pick_host
  say "== sync pack on $HOST =="
  say "sync.conf: nixos=$NIXOS presets=$PRESETS sudo=$SUDO rebuild=$REBUILD"
  [ -d "$NIXOS" ] || stop "the nixos dir $NIXOS is missing."
  [ -d "$PRESETS" ] || stop "the presets dir $PRESETS is missing."
  say "the nixos dir and the presets dir are present."

  say "checking the nixos working tree (git status --porcelain) ..."
  local st
  st=$(ngit status --porcelain) || stop "git status failed in $NIXOS."
  if [ -n "$st" ]; then
    say "$st"
    stop "the nixos working tree has changes (listed above). Commit them first. Nothing was packed."
  fi
  say "clean."

  say "checking that no tracked nixos file contains a CR byte ..."
  local tracked f rc
  local -a crs=()
  tracked=$(ngit ls-files -z | tr '\0' '\n') || stop "git ls-files failed in $NIXOS."
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    nrun grep -q -U -e $'\r' -- "$NIXOS/$f" && rc=0 || rc=$?
    case $rc in
      0) crs+=("$f") ;;
      1) ;;
      *) stop "cannot read $NIXOS/$f." ;;
    esac
  done <<< "$tracked"
  if [ "${#crs[@]}" -gt 0 ]; then
    printf '%s\n' "${crs[@]}" | out
    stop "these tracked nixos files contain CR bytes (listed above). Nothing was packed."
  fi
  say "none."

  local utc outdir name pkg
  utc=$(date -u +%Y%m%dT%H%M%SZ)
  mkdir -p "$1" || stop "cannot make $1."
  outdir=$(cd "$1" && pwd)
  name=bastion-sync-$utc
  pkg=$outdir/$name
  mkdir "$pkg" || stop "cannot make $pkg."
  say "made $pkg"

  say "making nixos.bundle (git bundle create --all) ..."
  ngit bundle create "$pkg/nixos.bundle" --all 2>&1 | out || stop "git bundle create failed (above)."
  say "nixos.bundle: $(wc -c < "$pkg/nixos.bundle" | tr -d ' ') bytes."

  say "listing the presets files (without presets.img, _archive/presets.img, sync/incoming/, bastion/state/) ..."
  local list
  local -a files
  list=$(cd "$PRESETS" && find . \( -path ./presets.img -o -path ./_archive/presets.img -o -path ./sync/incoming -o -path ./bastion/state \) -prune \
    -o \( -type f -o -type l \) -print | sed 's|^\./||' | LC_ALL=C sort) || stop "cannot list $PRESETS."
  mapfile -t files <<< "$list"
  say "making presets.tar (${#files[@]} files) ..."
  tar -C "$PRESETS" -cf - -- "${files[@]}" > "$pkg/presets.tar" || stop "tar of the presets files failed."
  say "presets.tar: $(wc -c < "$pkg/presets.tar" | tr -d ' ') bytes."

  local count head branch
  count=$(tar -tf - < "$pkg/presets.tar" | wc -l | tr -d ' ') || stop "cannot read presets.tar."
  head=$(ngit rev-parse HEAD) || stop "cannot read the nixos HEAD."
  branch=$(ngit symbolic-ref --short HEAD) || stop "the nixos dir has no current branch."
  say "writing MANIFEST ..."
  printf '%s\n' "host=$HOST" "utc=$utc" "nixos_head=$head" "nixos_branch=$branch" "presets_files=$count" > "$pkg/MANIFEST"
  out < "$pkg/MANIFEST"

  say "writing SHA256SUMS ..."
  { (cd "$pkg" && sha256sum nixos.bundle presets.tar MANIFEST) &&
    (cd "$PRESETS" && sha256sum -- "${files[@]}") | sed -E 's#^([0-9a-f]{64}) ([ *])#\1 \2presets/#'
  } > "$pkg/SHA256SUMS" || stop "sha256sum failed."
  say "$(wc -l < "$pkg/SHA256SUMS" | tr -d ' ') hashes written."

  say "making $outdir/$name.tar ..."
  tar -C "$outdir" -cf - "$name" > "$outdir/$name.tar" || stop "tar of $pkg failed."
  say "ALL OK. The archive: $outdir/$name.tar"
}

cmd_unpack() {
  [ $# -eq 1 ] || usage
  pick_host
  local tarf=$1
  [ -f "$tarf" ] || stop "no file $tarf."
  [ -d "$NIXOS" ] || stop "the nixos dir $NIXOS is missing."
  [ -d "$PRESETS" ] || stop "the presets dir $PRESETS is missing."
  local top utc in
  top=$(tar -tf - < "$tarf" | sed -n '1s|/.*||p') || stop "cannot read $tarf as a tar."
  case $top in bastion-sync-*) ;; *) stop "$tarf was not made by sync.sh pack (its first entry is '$top')." ;; esac
  utc=${top#bastion-sync-}
  mkdir -p "$PRESETS/sync/incoming/$utc" || stop "cannot make $PRESETS/sync/incoming/$utc."
  in=$(cd "$PRESETS/sync/incoming/$utc" && pwd)
  LOG=$in/log.txt
  say "== sync unpack on $HOST at $(date -u +%Y%m%dT%H%M%SZ) =="
  say "sync.conf: nixos=$NIXOS presets=$PRESETS sudo=$SUDO rebuild=$REBUILD"
  say "archive: $tarf (left where it is)"

  say "extracting the archive into $in ..."
  tar -C "$in" --strip-components=1 -xf - < "$tarf" || stop "extracting $tarf failed."
  say "MANIFEST:"
  out < "$in/MANIFEST"

  say "checking the hashes of nixos.bundle, presets.tar and MANIFEST ..."
  local three
  three=$(grep -E '^[0-9a-f]{64} [ *](nixos\.bundle|presets\.tar|MANIFEST)$' "$in/SHA256SUMS") || true
  [ "$(printf '%s\n' "$three" | grep -c .)" = 3 ] || stop "SHA256SUMS does not list nixos.bundle, presets.tar and MANIFEST."
  (cd "$in" && printf '%s\n' "$three" | sha256sum -c -) 2>&1 | out || stop "a hash does not match (above). Nothing was changed."

  say "checking the bundle against the nixos dir (git bundle verify) ..."
  ngit bundle verify "$in/nixos.bundle" 2>&1 | out || stop "git bundle verify failed (above). Nothing was changed."

  say "fetching the bundle's branches into refs/remotes/sync/ ..."
  ngit fetch "$in/nixos.bundle" '+refs/heads/*:refs/remotes/sync/*' 2>&1 | out || stop "git fetch failed (above)."
  local b sb lg ds
  b=$(ngit symbolic-ref --short HEAD) || stop "the nixos dir has no current branch."
  sb=refs/remotes/sync/$b
  ngit rev-parse -q --verify "$sb" > /dev/null || stop "the archive has no branch $b."
  say "current branch: $b"
  say "commits that come in (git log --oneline HEAD..sync/$b):"
  lg=$(ngit --no-pager log --oneline "HEAD..$sb") || stop "git log failed."
  say "${lg:-(none)}"
  say "files that change (git diff --stat HEAD sync/$b):"
  ds=$(ngit --no-pager diff --stat HEAD "$sb") || stop "git diff failed."
  say "${ds:-(none)}"

  local st=$in/presets n
  say "extracting presets.tar into $st ..."
  mkdir -p "$st" || stop "cannot make $st."
  tar -C "$st" -xf - < "$in/presets.tar" || stop "extracting presets.tar failed."
  say "checking every presets file hash ..."
  n=$(grep -cE '^[0-9a-f]{64} [ *]presets/' "$in/SHA256SUMS") || stop "SHA256SUMS lists no presets files."
  [ "$n" = "$(tar -tf - < "$in/presets.tar" | wc -l | tr -d ' ')" ] || stop "SHA256SUMS lists $n presets files, presets.tar holds another number."
  (cd "$in" && grep -E '^[0-9a-f]{64} [ *]presets/' SHA256SUMS | sha256sum -c --quiet -) 2>&1 | out || stop "a presets file does not match its hash (above). Nothing was changed."
  say "all $n presets files match."

  say "presets files that differ from $PRESETS (added or changed; nothing is ever deleted there):"
  local rel diffs=0
  while IFS= read -r rel; do
    if [ ! -e "$PRESETS/$rel" ] && [ ! -L "$PRESETS/$rel" ]; then
      say "  added:   $rel"; diffs=$((diffs + 1))
    elif ! cmp -s "$st/$rel" "$PRESETS/$rel"; then
      say "  changed: $rel"; diffs=$((diffs + 1))
    fi
  done < <(tar -tf - < "$in/presets.tar")
  say "$diffs presets files differ."

  say "Press Enter to apply, Ctrl-C to stop."
  read -r _ || stop "no Enter read. Nothing was changed."

  say "nixos: checking modified tracked files against sync/$b ..."
  local ps entry xy p skip=
  local -a mods=() bad=()
  ps=$(ngit status --porcelain -z | tr '\0' '\n') || stop "git status failed in $NIXOS."
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if [ -n "$skip" ]; then skip=; continue; fi
    xy=${entry:0:2}; p=${entry:3}
    case $xy in R*|C*) skip=1 ;; esac
    case $xy in *M*) mods+=("$p") ;; esac
  done <<< "$ps"
  for p in "${mods[@]}"; do
    if ngit cat-file -p "$sb:$p" 2> /dev/null | nrun cmp -s - "$NIXOS/$p"; then
      say "  same as sync/$b: $p"
    else
      say "  differs from sync/$b: $p"; bad+=("$p")
    fi
  done
  [ "${#bad[@]}" -eq 0 ] || stop "these modified files differ from the incoming ones (listed above). Nothing was changed."
  if [ "${#mods[@]}" -gt 0 ]; then
    ngit checkout "$sb" -- "${mods[@]}" 2>&1 | out || stop "git checkout from sync/$b failed (above)."
    say "checked out ${#mods[@]} files from sync/$b."
  else
    say "no modified tracked files."
  fi
  say "nixos: git merge --ff-only sync/$b ..."
  ngit merge --ff-only "$sb" 2>&1 | out || stop "the fast-forward failed (message above). The presets were not touched."
  say "nixos HEAD is now $(ngit rev-parse HEAD)."

  say "presets: copying the staged files over $PRESETS (overwrite, never delete) ..."
  cp -R "$st/." "$PRESETS/" || stop "copying the presets failed."
  say "presets: checking every hash again on the installed files ..."
  (cd "$PRESETS" && grep -E '^[0-9a-f]{64} [ *]presets/' "$in/SHA256SUMS" \
    | sed -E 's#^([0-9a-f]{64}) ([ *])presets/#\1 \2#' | sha256sum -c --quiet -) 2>&1 | out \
    || stop "an installed presets file does not match its hash (above)."
  say "all $n installed presets files match."

  if [ "$REBUILD" = no ]; then
    say "rebuild=no for $HOST: no nixos-rebuild here."
  else
    say "Press Enter to run nixos-rebuild switch, Ctrl-C to stop."
    read -r _ || stop "no Enter read. No rebuild."
    say "running: sudo nixos-rebuild switch --flake $NIXOS#$REBUILD"
    sudo nixos-rebuild switch --flake "$NIXOS#$REBUILD" 2>&1 | out || stop "nixos-rebuild switch failed (above)."
  fi
  say "ALL OK. Log: $LOG"
}

case ${1:-} in
  pack) shift; cmd_pack "$@" ;;
  unpack) shift; cmd_unpack "$@" ;;
  *) usage ;;
esac
