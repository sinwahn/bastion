# /etc/nixos/modules/host/firmware.nix
# Firmware: fwupd, which reads the list of available firmware from LVFS.
# Installing firmware is always a separate decision with its own steps.
# A plugin of fwupd that a machine turns off is set in its own folder
# (hosts/bastion/default.nix).

{ config, pkgs, ... }:

{
  services.fwupd.enable = true;
}
