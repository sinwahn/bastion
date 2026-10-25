# /etc/nixos/modules/host/users.nix
# Your account. Its password was set by the installer, not in this file.

{ config, pkgs, local, ... }:

{
  # wheel: you may use sudo. networkmanager: you may change networks.
  users.users.${local.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
}
