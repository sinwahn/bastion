# The host's uplinks of uplinks.nix, one NetworkManager profile each, named
# after its entry; the allowance (never-default, the DNS) and the
# preference (the route metrics) are gate's at runtime.
{ config, lib, pkgs, ... }:

let
  inherit (import ./station-roles.nix { inherit lib; }) hostIp;
  inherit (import ./uplink-roles.nix { inherit lib; }) uplinkList uplinks uplinksThroughVms cables dnsOf cableLink;
  uplinkFunctions = import ./uplink-functions.nix { inherit config lib pkgs; };
  # nmcli adds every profile as type ethernet and shows its type back as
  # 802-3-ethernet. A cable's profile takes connection.autoconnect from its
  # route only when it is made: it connects by itself only while the route
  # is direct to the host, and so keeps the route across restarts.
  declaredFields = u: "connection.interface-name ${u.device} " + (
    if u ? gateway then
      "connection.autoconnect yes ipv4.method manual ipv4.addresses ${hostIp}/${toString u.prefix} ipv4.gateway ${u.gateway}"
    else "ipv4.method auto");
  madeFields = u: lib.optionalString (u ? vendor)
    "connection.autoconnect \${ac:-${if u.kind == "vm" then "no" else "yes"}}";
  # A profile of another type (wifi was once a bridge profile) is removed
  # and added again from the list, its allowance and its connecting by
  # itself carried over.
  ensureStep = pkgs.writeShellScript "uplinks-ensure" ''
    set -u
    . ${uplinkFunctions}
    pref=''${1:-$(preferred)}
    rp=" $(rerouted) "
    ${lib.concatStrings (lib.mapAttrsToList (n: u: ''
    nd=yes
    ac=
    t=$(nm -g connection.type connection show ${n} 2>/dev/null) || t=
    if [ -n "$t" ] && [ "$t" != 802-3-ethernet ]; then
      if allowed ${n}; then nd=no; fi
      ac=$(nm -g connection.autoconnect connection show ${n})
      nm connection delete ${n} >/dev/null
    fi
    nm connection show ${n} >/dev/null 2>&1 \
      || nm connection add type ethernet con-name ${n} ${declaredFields u} ${madeFields u} ipv4.never-default $nd ipv6.never-default $nd ipv4.ignore-auto-dns $nd ipv6.ignore-auto-dns $nd >/dev/null
    if allowed ${n}; then d="${dnsOf u}"; else d=; fi
    m=${toString uplinkList.metric.others}
    ${if u ? gateway then ''
    case " ${n}$rp" in *" $pref "*) m=${toString uplinkList.metric.preferred} ;; esac
    '' else ''
    case "$rp" in *" ${n} "*) ;; *) if [ "$pref" = ${n} ]; then m=${toString uplinkList.metric.preferred}; fi ;; esac
    ''}apply ${n} ${declaredFields u} ipv4.dns "$d" ipv4.route-metric "$m" ipv6.route-metric "$m"
    '') uplinks)}'';
in
{
  # NetworkManager's own udev rule (85-nm-unmanaged.rules) leaves a veth
  # unmanaged; a device section with managed outranks it, so the profile of
  # the uplink through the VMs comes up by itself at every boot. A module of
  # its own, since settings.main is set below.
  imports = [ {
    networking.networkmanager.settings = lib.mapAttrs' (n: u: lib.nameValuePair "device-${u.device}" {
      match-device = "interface-name:${u.device}";
      managed = true;
    }) uplinksThroughVms;
  } ];

  systemd.network.links = lib.mapAttrs' (n: u: lib.nameValuePair "10-${n}" (cableLink u.device u)) cables;
  # A cable carries nothing until gate allows it.
  networking.networkmanager.settings.main.no-auto-default =
    lib.concatMapStringsSep ";" (u: "interface-name:${u.device}") (lib.attrValues uplinks);
  systemd.services.uplinks-ensure = {
    description = "The host's uplink profiles of uplinks.nix";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" ];
    path = [ pkgs.coreutils pkgs.gnugrep ];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = "${ensureStep}";
  };
  # With two uplinks a reply may come in over the one that does not carry
  # the default route.
  networking.firewall.checkReversePath = "loose";
}
