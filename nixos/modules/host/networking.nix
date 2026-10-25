# /etc/nixos/modules/host/networking.nix
# Host name and network.

{ config, pkgs, ... }:

{
  networking.hostName = "bastion";
  networking.networkmanager.enable = true;
}
