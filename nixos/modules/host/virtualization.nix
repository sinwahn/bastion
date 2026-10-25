# /etc/nixos/modules/host/virtualization.nix
# Workstations on the host. KVM is in the kernel, QEMU runs each
# workstation, libvirt manages them, virt-manager shows them.
# "virtualisation." below is the name NixOS gives these options; it cannot be changed.

{ config, pkgs, local, ... }:

{
  # libvirt, the service that starts and stops workstations (libvirtd).
  virtualisation.libvirtd.enable = true;

  # QEMU runs as its own user, qemu-libvirtd, not as root.
  virtualisation.libvirtd.qemu.runAsRoot = false;

  # swtpm: an emulated TPM 2.0 chip for workstations.
  virtualisation.libvirtd.qemu.swtpm.enable = true;

  # UEFI firmware (OVMF) needs no line: NixOS 26.05 offers the firmware
  # files that come with QEMU to libvirt by itself.

  # Host shutdown or restart: running workstations are shut down.
  virtualisation.libvirtd.onShutdown = "shutdown";

  # Host start: no workstation starts again by itself.
  virtualisation.libvirtd.onBoot = "ignore";

  # virt-manager, the window for workstations.
  programs.virt-manager.enable = true;

  # The owner's user of local.nix may manage workstations without typing a password.
  users.users.${local.user}.extraGroups = [ "libvirtd" ];

  # swtpm runs as its own user tss, not as root.
  users.users.tss = {
    isSystemUser = true;
    group = "tss";
  };
  users.groups.tss = { };

  environment.systemPackages = [
    # lspci lists the devices on the PCI connection.
    pkgs.pciutils

    # iommu-groups prints every IOMMU group and the devices in it.
    (pkgs.writeShellScriptBin "iommu-groups" ''
      for g in $(ls /sys/kernel/iommu_groups | sort -n); do
        echo "IOMMU group $g:"
        for d in $(ls /sys/kernel/iommu_groups/$g/devices); do
          ${pkgs.pciutils}/bin/lspci -nns "$d"
        done
      done
    '')

    # usb-by-controller prints each USB device and the path to its
    # USB controller.
    (pkgs.writeShellScriptBin "usb-by-controller" ''
      for d in /sys/bus/usb/devices/*; do
        [ -e "$d/idVendor" ] || continue
        echo "$(basename "$d") $(cat "$d/idVendor"):$(cat "$d/idProduct") $(cat "$d/product" 2>/dev/null) at $(readlink -f "$d")"
      done
    '')
  ];
}
