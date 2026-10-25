# /etc/nixos/modules/host/desktop.nix
# Desktop: KDE Plasma 6 with the SDDM login screen, and Firefox.

{ config, pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  programs.firefox.enable = true;
}
