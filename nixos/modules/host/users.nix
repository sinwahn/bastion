# The account's password was set by the installer, not in this file.
{ config, pkgs, local, ... }:

{
  users.users.${local.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
}
