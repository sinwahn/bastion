# /etc/nixos/flake.nix
{
  description = "Bastion standard repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix/f13928fe9900e91709d7ce581eefa47eaafa79e1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, microvm, ... }: {
    nixosConfigurations.bastion = nixpkgs.lib.nixosSystem {
      # local.nix holds the machine's own values and stands only in the
      # machine's private clone (README.md); every module receives them as
      # local. Every module also receives the flake input nixos-hardware, so
      # that the machine's folder hosts/bastion imports its board module.
      specialArgs = { local = import ./local.nix; inherit nixos-hardware; };
      modules = [
        # The machine's own folder, in the machine's private clone only
        # (README.md): its hardware scan, its board module, its time zone,
        # locale and keyboard, its card's ids and its machine-only modules.
        ./hosts/bastion/default.nix
        ./modules/host/boot.nix
        ./modules/host/networking.nix
        ./modules/host/desktop.nix
        ./modules/host/users.nix
        ./modules/host/nix.nix
        ./modules/host/firmware.nix
        ./modules/host/virtualization.nix
        ./modules/host/vfio.nix
        ./modules/host/looking-glass.nix
        ./modules/host/bluetooth.nix
        ./modules/bastion/bastion.nix
        microvm.nixosModules.host
        ./modules/isolation/host.nix
        ./modules/isolation/net.nix
        ./modules/isolation/gateway.nix
        ./modules/isolation/broker.nix
      ];
    };
  };
}
