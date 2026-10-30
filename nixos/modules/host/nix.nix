{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # git, because the standard repository is a git repository.
  # e2fsprogs for lsattr, which shows copy-on-write.
  environment.systemPackages = with pkgs; [
    git
    e2fsprogs
  ];

  # These lines add nothing to the built system. They stop a rebuild with an
  # error if any setting turns signature checking off, adds another binary
  # cache, or trusts another signing key.
  assertions = [
    {
      assertion = config.nix.settings.require-sigs == true;
      message = "Bastion: nix.settings.require-sigs must stay true.";
    }
    {
      assertion = config.nix.settings.substituters == [ "https://cache.nixos.org/" ];
      message = "Bastion: the only binary cache is https://cache.nixos.org/.";
    }
    {
      assertion = config.nix.settings.trusted-public-keys == [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
      message = "Bastion: the only trusted signing key is the cache.nixos.org key.";
    }
  ];
}
