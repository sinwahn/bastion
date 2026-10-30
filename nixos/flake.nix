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
      # local.nix and hosts/bastion stand only in the machine's private clone
      # (README.md); the machine's folder imports its board module through
      # the flake input nixos-hardware.
      specialArgs = { local = import ./local.nix; inherit nixos-hardware; };
      # The order keeps the order of every list that several modules extend.
      modules = [
        ./hosts/bastion/default.nix
        ./modules/host/boot.nix
        ./modules/host/networking.nix
        ./modules/host/desktop.nix
        ./modules/host/users.nix
        ./modules/host/nix.nix
        ./modules/host/firmware.nix
        ./modules/host/virtualization.nix
        ./modules/host/vfio.nix
        ./modules/looking-glass/looking-glass.nix
        ./modules/host/bluetooth.nix
        ./modules/bastion/bastion.nix
        microvm.nixosModules.host
        ./modules/networks/switches.nix
        ./modules/networks/host-cable.nix
        ./modules/networks/networks-apply.nix
        ./modules/service-vms/no-memory-merging.nix
        ./modules/service-vms/journals.nix
        ./modules/networks/uplink-profiles.nix
        ./modules/networks/cable-reroute.nix
        ./modules/gate/gate.nix
        ./modules/service-vms/wifi-vm.nix
        ./modules/service-vms/wifi-vm-uplinks.nix
        ./modules/service-vms/wifi-vm-cable-profiles.nix
        ./modules/service-vms/firewall-vm.nix
        ./modules/service-vms/firewall-rules.nix
        ./modules/broker/broker-vm.nix
        ./modules/broker/exchange-folders.nix
      ];
    };
  };
}
