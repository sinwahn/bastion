# /etc/nixos/modules/host/boot.nix
# The start of the system: boot loader, kernel settings, kernel modules.

{ config, pkgs, ... }:

{
  # Boot loader: systemd-boot.
  boot.loader.systemd-boot.enable = true;
  # No editing of the start command line in the boot menu.
  boot.loader.systemd-boot.editor = false;
  boot.loader.efi.canTouchEfiVariables = true;
  # The newest kernel series.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # No hibernation.
  boot.kernelParams = [ "nohibernate" ];

  # Keep nouveau, the open NVIDIA driver, off the host.
  boot.blacklistedKernelModules = [ "nouveau" ];
}
