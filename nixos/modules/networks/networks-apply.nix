{ lib, pkgs, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  switches = hostNetworks.switches;
  liveDataFile = hostNetworks."networks.json";
  inherit (import ./station-roles.nix { inherit lib; }) vmStations hostEntry;
  inherit (import ./uplink-roles.nix { inherit lib; }) uplinksThroughVms;
  cablesOnSwitch = import ./switch-cables.nix { inherit lib; };
  switchUnits = map (s: "${s}-netdev.service") (lib.attrValues switches);
  tapUnits = map (v: "microvm-tap-interfaces@${v}.service") (lib.attrValues hostNetworks.vms);
  # The switch's default (untagged) VLAN, the one a cable is on when it
  # joins the switch, which libvirt also counts on
  # (src/util/virnetdevbridge.c 323-324).
  kWorkstationsVlan = 1;
  firstWrite = builtins.toJSON {
    network = switches.workstations;
    lane = kWorkstationsVlan;
    inherit (lib.head (lib.attrValues uplinksThroughVms)) gateway prefix;
    stations = vmStations;
  };
  kGuardTable = "ws-guard";
  liveDataFileStep = ''
    file=${liveDataFile}
    table=${kGuardTable}
    hostport=${hostEntry}
    switch=${switches.workstations}
    cable=${hostNetworks.cables.firewall-vm.name}
    untagged=${toString kWorkstationsVlan}
    ports=${lib.escapeShellArg (lib.concatMapStringsSep ", " (n: "\"${n}\"") (cablesOnSwitch switches.workstations))}
    first=${lib.escapeShellArg firstWrite}
  '' + builtins.readFile ../scripts/networks-apply.sh;
in
{
  # A drop-in on microvm.nix's unit, the way microvm.nix adds its own; a
  # module of its own, since systemd.services is set below.
  imports = [ {
    systemd.services = lib.genAttrs (map (v: "microvm-tap-interfaces@${v}") (lib.attrValues hostNetworks.vms)) (v: {
      wants = [ "networks-apply.service" ];
      before = [ "networks-apply.service" ];
    });
  } ];

  # Part of each switch's and cable's unit, so it runs again whenever one of
  # them is made again; a rebuild leaves the guard to it, since the guard is
  # no table of networking.nftables.
  systemd.services.networks-apply = {
    description = "The service VMs' cables of host-networks.nix on their switches, and the guard from the live data file";
    wantedBy = switchUnits;
    partOf = switchUnits ++ tapUnits;
    after = switchUnits ++ tapUnits;
    # The live data file must be there when firewall-apply reads it at
    # firewall-vm's start.
    before = [ "microvm@${hostNetworks.vms.firewall-vm}.service" ];
    path = [ pkgs.iproute2 pkgs.nftables pkgs.jq ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = lib.concatMapStrings (c: ''
      if [ -e /sys/class/net/${c.name} ]; then
        ip link set dev ${c.name} master ${switches.${c.switch}}
      else
        echo "${c.name} is not on ${switches.${c.switch}}: there is no device of that name; its VM is stopped, or no service VM has it in its interfaces."
      fi
    '') (lib.attrValues hostNetworks.cables) + liveDataFileStep;
  };

  networking.nftables.enable = true;
}
