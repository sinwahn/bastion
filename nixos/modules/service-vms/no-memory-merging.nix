# microvm.nix turns memory merging (KSM) on by default.
{ ... }:

{
  hardware.ksm.enable = false;
}
