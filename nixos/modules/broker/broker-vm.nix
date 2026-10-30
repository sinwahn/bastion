# broker-vm owns the exchange of files between the VMs and has no network
# at all: the host reaches it over vsock alone, and no VM reaches it.
{ config, lib, pkgs, ... }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  brokerVm = hostNetworks.vms.broker-vm;
  exchange = hostNetworks.exchange;
  liveDataFile = hostNetworks."networks.json";
  liveDataFolder = dirOf liveDataFile;
  inherit (import ../networks/station-roles.nix { inherit lib; }) hostEntry;
  serviceVm = import ../service-vms/service-vm.nix { inherit config lib; };
  # This VM's sshd reads the public half from the shared folder of the live
  # data file.
  brokerKey = "${dirOf exchange.key}/${brokerVm}";
  publicHalf = key: "${liveDataFolder}/${baseNameOf key}.pub";
  kKeptCopiesFolder = "/exchange";
  # A take is refused when the kept copies would pass this percent of their
  # volume's size.
  kLimitPercent = 80;
  programWords = lib.concatMapStrings (g: lib.concatStrings (lib.mapAttrsToList
    (k: v: "${g}_${k}=${lib.escapeShellArg v}\n") exchange.${g})) [ "verbs" "log" "reasons" ];
  # sshd runs the broker's program at every login of the host, whatever
  # command the host gave, which the program takes from
  # SSH_ORIGINAL_COMMAND.
  brokerProgram = pkgs.writeShellScript brokerVm (''
    export PATH=${lib.makeBinPath [ pkgs.jq pkgs.coreutils pkgs.util-linux ]}
    set -u
    file=${liveDataFile}
    root=${kKeptCopiesFolder}
    percent=${toString kLimitPercent}
    host=${hostEntry}
    key=${lib.escapeShellArg exchange.sends-to}
    tag=${brokerVm}
    ${programWords}
  '' + builtins.readFile ../scripts/broker-program.sh);
in
{
  config = lib.mkMerge [
    (serviceVm {
      name = brokerVm;
      mem = 512;
      vsockNumber = 12;
      volumes = [ {
        image = "exchange.img";
        mountPoint = kKeptCopiesFolder;
        size = 20480;
      } ];
      login = true;
      sharesLiveDataFolder = true;
    })
    {
      microvm.vms.${brokerVm}.config = {
        services.journald.extraConfig = "SystemMaxUse=1G";
        # NixOS adds the home folder's file and its own folder's file to
        # this list; the one file stands alone only when forced.
        services.openssh.authorizedKeysFiles = lib.mkForce [ (publicHalf brokerKey) ];
        services.openssh.extraConfig = ''
          AllowUsers root
          ForceCommand ${brokerProgram}
          PermitTTY no
          DisableForwarding yes
        '';
      };

      # Before broker-vm starts, whose sshd reads the public half of the key
      # named after it.
      systemd.services."${brokerVm}-keys" = {
        description = "The host's keys for ${brokerVm} and for the VMs' exchange accounts, their public halves in ${liveDataFolder}";
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
    }
  ];
}
