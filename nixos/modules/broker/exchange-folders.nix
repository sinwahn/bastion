{ ... }:

let
  exchange = (import ../isolation/host-networks.nix).exchange;
in
{
  systemd.tmpfiles.rules = map (d: "d ${d} 0700 root root -") [ exchange.staging exchange.inbox ];
}
