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
  d=${d%x}
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
set -- ${SSH_ORIGINAL_COMMAND:-}
set +f
verb=${1:-}
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
  sum=${sum%% *}
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
    note "$log_cleaned" "$vm" "" "${f##*/}" "$n" "${sum%% *}" ""
    rm -f "$f"
    count=$((count + 1)) bytes=$((bytes + n))
  done
  printf '%s, %s\n' "$count" "$bytes"
  ;;
*)
  refuse "" "" "" "" "$reasons_command"
  ;;
esac
