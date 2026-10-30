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
