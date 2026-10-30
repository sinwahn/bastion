# The example of a machine's own folder. In the machine's private clone,
# copy this folder to nixos/hosts/bastion/, which the flake imports, and
# write the machine's values in place of the words in capitals (README.md).
# Everything in that folder belongs to the one machine and is committed
# only in its private clone.

{ config, pkgs, nixos-hardware, ... }:

let
  hostNetworks = import ../../modules/isolation/host-networks.nix;
in
{
  imports = [
    # The machine's board module of nixos-hardware, when there is one for
    # it: its name in place of BOARD.
    nixos-hardware.nixosModules.BOARD

    # The hardware scan, which nixos-generate-config writes when NixOS is
    # installed on the machine.
    ./hardware-configuration.nix

    # Any module of this machine alone, one file in this folder each, such
    # as a VM defined in Nix or a setting the board module turns on that
    # the machine turns off.
  ];

  # The machine's time zone and language.
  time.timeZone = "TIMEZONE";
  i18n.defaultLocale = "LOCALE";

  # The machine's keyboard: the console keymap is used on text screens and
  # at the passphrase prompt, the X keyboard layout by the login screen and
  # the desktop.
  console.keyMap = "KEYMAP";
  services.xserver.xkb.layout = "KEYMAP";

  # The vendor:device IDs of every function in the IOMMU group of the card
  # a VM takes; vfio-pci takes these functions while the host starts
  # (modules/host/vfio.nix).
  boot.kernelParams = [ "vfio-pci.ids=0000:0000,0000:0000" ];

  # The country whose radio rules the Wi-Fi VM follows
  # (modules/service-vms/wifi-vm.nix).
  microvm.vms.${hostNetworks.vms.wifi-vm}.config = {
    boot.extraModprobeConfig = "options cfg80211 ieee80211_regdom=COUNTRY";
  };

  # The machine's folder also holds what its own disks and its install
  # need: mount options, the folders of the VM disks
  # (/var/lib/libvirt/images, /var/lib/microvms) as its file system keeps
  # them, its swap and its system.stateVersion.
}
