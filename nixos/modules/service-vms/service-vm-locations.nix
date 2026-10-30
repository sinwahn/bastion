# Not a module: where the host finds a service VM, read from its own
# module's configuration.
{ config, lib }:

let
  vmConfig = name: config.microvm.vms.${name}.config.config;
  journalId = name: lib.replaceStrings [ "-" ] [ "" ] (vmConfig name).microvm.machineId;
in
{
  inherit journalId;
  vsockNumber = name: toString (vmConfig name).microvm.vsock.cid;
  # microvm.nix keeps the socket in the VM's state folder when it is not a
  # whole path.
  controlSocket = name: let s = (vmConfig name).microvm.socket; in
    if lib.hasPrefix "/" s then s else "${config.microvm.stateDir}/${name}/${s}";
  journalFolder = name: "${config.microvm.stateDir}/${name}/journal/${journalId name}";
}
