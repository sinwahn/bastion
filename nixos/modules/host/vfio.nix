# /etc/nixos/modules/host/vfio.nix
# Hold the card that a VM takes away from the host (static binding).
# vfio-pci takes the card's functions while the host starts,
# so no other driver on the host can take them.

{ config, pkgs, ... }:

{
  # Load the VFIO modules in the first stage of the start (initrd),
  # before the card's other drivers can start.
  boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];

  # The vendor:device IDs of every function in the card's IOMMU group are
  # the machine's own: its folder (hosts/bastion/default.nix) hands them to
  # vfio-pci as the kernel parameter vfio-pci.ids.

  # Keep the open NVIDIA drivers off the host. nouveau is already kept off
  # in boot.nix; nova_core and nova (named nova_drm from Linux 7.2)
  # are not built in the NixOS 26.05 kernels and are listed so that a later
  # kernel cannot load them by itself.
  boot.blacklistedKernelModules = [ "nova_core" "nova" "nova_drm" ];
}
