# Looking Glass on the host, for the VMs that hold a card passed to them.
# The client is built from the same source commit as the Windows IDD
# installer used inside the VMs; /etc/looking-glass-host.json names that
# installer for attach.sh: the build, the address the Looking Glass project
# serves it at and the installer's sha256.
{ config, lib, pkgs, local, ... }:

let
  kLookingGlassCommit = "cdba29f2f6bcae3ded26369fc231a067cbca3752";
  udevRule = import ../host/udev-rule.nix { inherit lib; };
  lookingGlassClient = pkgs.looking-glass-client.overrideAttrs (old: {
    version = "B7-829-${builtins.substring 0 8 kLookingGlassCommit}";
    src = pkgs.fetchFromGitHub {
      owner = "gnif";
      repo = "LookingGlass";
      rev = kLookingGlassCommit;
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

  # The client reads /dev/kvmfr0 as the owner's user; QEMU runs as the user
  # qemu-libvirtd, not as root.
  services.udev.extraRules = udevRule [ [ "SUBSYSTEM" "kvmfr" ] ]
    [ [ "OWNER" local.user ] [ "GROUP" "qemu-libvirtd" ] [ "MODE" "0660" ] ];

  # libvirt lets QEMU use only the devices this list names.
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
