# Not a module: one function builds every service VM's definition, a
# microVM of microvm.nix started with the host; its parameters are what
# differs between the service VMs.
{ config, lib }:

let
  hostNetworks = import ../isolation/host-networks.nix;
  liveDataFolder = dirOf hostNetworks."networks.json";
  # sshd's host key lives on a volume of its own: on the tmpfs root a fresh
  # key was made at every boot and the host refused it after each restart.
  kHostKeysFolder = "/var/lib/ssh-host-keys";
in
{ name, mem, vsockNumber, interfaces ? [ ], volumes ? [ ], login ? false, sharesLiveDataFolder ? false }:
{
  microvm.vms.${name}.config = lib.mkMerge [
    {
      system.stateVersion = "26.05";
      microvm = {
        hypervisor = "qemu";
        vcpu = 1;
        inherit mem;
        interfaces = map (i: { type = "tap"; id = i.cable; inherit (i) mac; }) interfaces;
        volumes = volumes ++ lib.optional login {
          image = "ssh-host-keys.img";
          mountPoint = kHostKeysFolder;
          size = 16;
        };
        shares = [ {
          proto = "virtiofs";
          tag = "journal";
          socket = "journal.sock";
          source = "${config.microvm.stateDir}/${name}/journal";
          mountPoint = "/var/log/journal";
        } ] ++ lib.optional sharesLiveDataFolder {
          proto = "virtiofs";
          tag = baseNameOf liveDataFolder;
          source = liveDataFolder;
          mountPoint = liveDataFolder;
          readOnly = true;
        };
        vsock.cid = vsockNumber;
      };
    }
    # A cable inside a service VM is named after where it leads.
    (lib.mkIf (interfaces != [ ]) {
      systemd.network.enable = true;
      networking.useDHCP = false;
      systemd.network.links = lib.listToAttrs (map (i: lib.nameValuePair "10-${i.leadsTo}" {
        matchConfig.MACAddress = i.mac;
        linkConfig.Name = i.leadsTo;
      }) interfaces);
      systemd.network.networks = lib.listToAttrs (map (i: lib.nameValuePair "10-${i.leadsTo}" ({
        matchConfig.Name = i.leadsTo;
        networkConfig.IPv6AcceptRA = false;
      } // i.network)) interfaces);
    })
    # Only the host reaches the login, over vsock (no network), with its key.
    (lib.mkIf login {
      microvm.vsock.ssh.enable = true;
      services.openssh.listenAddresses = [ { addr = "127.0.0.1"; port = 22; } ];
      services.openssh.hostKeys = [ { type = "ed25519"; path = "${kHostKeysFolder}/ssh_host_ed25519_key"; } ];
    })
  ];
}
