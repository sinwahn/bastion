# "virtualisation." is the name NixOS gives these options; it cannot be
# changed.
{ config, pkgs, local, ... }:

{
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.runAsRoot = false;
  virtualisation.libvirtd.qemu.swtpm.enable = true;

  # UEFI firmware (OVMF) needs no line: NixOS 26.05 offers the firmware
  # files that come with QEMU to libvirt by itself.

  virtualisation.libvirtd.onShutdown = "shutdown";
  virtualisation.libvirtd.onBoot = "ignore";

  programs.virt-manager.enable = true;

  users.users.${local.user}.extraGroups = [ "libvirtd" ];

  # swtpm runs as its own user tss, not as root.
  users.users.tss = {
    isSystemUser = true;
    group = "tss";
  };
  users.groups.tss = { };

  environment.systemPackages = [
    pkgs.pciutils
    (pkgs.writeShellScriptBin "iommu-groups" ''
      for g in $(ls /sys/kernel/iommu_groups | sort -n); do
        echo "IOMMU group $g:"
        for d in $(ls /sys/kernel/iommu_groups/$g/devices); do
          ${pkgs.pciutils}/bin/lspci -nns "$d"
        done
      done
    '')
    (pkgs.writeShellScriptBin "usb-by-controller" ''
      for d in /sys/bus/usb/devices/*; do
        [ -e "$d/idVendor" ] || continue
        echo "$(basename "$d") $(cat "$d/idVendor"):$(cat "$d/idProduct") $(cat "$d/product" 2>/dev/null) at $(readlink -f "$d")"
      done
    '')
  ];
}
