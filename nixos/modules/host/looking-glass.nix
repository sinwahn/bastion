# /etc/nixos/modules/host/looking-glass.nix
# Looking Glass on the host, for the VMs that hold a card passed to them.
# - The kernel module KVMFR makes 64 MiB of shared memory as /dev/kvmfr0.
# - /dev/kvmfr0 belongs to the owner's user of local.nix (the client reads it) and to the
#   group qemu-libvirtd (QEMU runs as that user, not as root).
# - libvirt lets QEMU use /dev/kvmfr0 (cgroup_device_acl).
# - The client is built from the same source commit as the Windows IDD
#   installer used inside the VMs (the build of version below).
# - /etc/looking-glass-host.json names that installer for attach.sh: the build, the address
#   the Looking Glass project serves it at and the installer's sha256.
# - The clipboard stays closed in both directions.
{ config, lib, pkgs, local, ... }:

let
  lookingGlassCommit = "cdba29f2f6bcae3ded26369fc231a067cbca3752";

  lookingGlassClient = pkgs.looking-glass-client.overrideAttrs (old: {
    version = "B7-829-cdba29f2";
    src = pkgs.fetchFromGitHub {
      owner = "gnif";
      repo = "LookingGlass";
      rev = lookingGlassCommit;
      hash = "sha256-/QE1Hre4Q7YplkudZZ7DSzmosY/MJc1XiAy69xcBXg4=";
      fetchSubmodules = true;
    };
    # The B7 patch of NixOS 26.05 is for the B7 source only.
    patches = [ ];
    # This source also needs fuse3, libdw (from elfutils) and libunwind.
    buildInputs = old.buildInputs ++ [
      pkgs.fuse3
      pkgs.elfutils
      pkgs.libunwind
    ];
  });
in
{
  boot.extraModulePackages = [ config.boot.kernelPackages.kvmfr ];
  boot.kernelModules = [ "kvmfr" ];
  boot.extraModprobeConfig = ''
    options kvmfr static_size_mb=64
  '';

  services.udev.extraRules = ''
    SUBSYSTEM=="kvmfr", OWNER="${local.user}", GROUP="qemu-libvirtd", MODE="0660"
  '';

  virtualisation.libvirtd.qemu.verbatimConfig = ''
    namespaces = []
    cgroup_device_acl = [
      "/dev/null", "/dev/full", "/dev/zero",
      "/dev/random", "/dev/urandom",
      "/dev/ptmx", "/dev/userfaultfd",
      "/dev/kvmfr0"
    ]
  '';

  environment.etc."looking-glass-client.ini".text = ''
    [input]
    escapeKey=KEY_CAPSLOCK

    [clipboard]
    toVM=no
    toLocal=no

    [spice]
    clipboard=no
  '';

  environment.etc."looking-glass-host.json".text = lib.generators.toJSON { } {
    build = lib.getVersion lookingGlassClient;
    url = "https://looking-glass.io/artifact/${lib.getVersion lookingGlassClient}/idd";
    sha256 = "1dd363a58ace6fd5e824d1a6c36744a58bbf181b739b3d75df669002cb1c68b5";
  };

  environment.systemPackages = [ lookingGlassClient ];
}
