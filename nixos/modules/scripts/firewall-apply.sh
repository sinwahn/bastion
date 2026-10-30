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
