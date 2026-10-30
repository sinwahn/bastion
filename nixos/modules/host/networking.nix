{ config, pkgs, ... }:

{
  networking.hostName = "bastion";
  networking.networkmanager.enable = true;
}
