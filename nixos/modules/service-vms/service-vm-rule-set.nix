# Not a module: one function puts every service VM's firewall rule set in
# that VM, with a copy to read in /etc/bastion named after the VM.
name: ruleset: {
  microvm.vms.${name}.config = {
    networking.firewall.enable = false;
    networking.nftables.enable = true;
    networking.nftables.ruleset = ruleset;
  };
  environment.etc."bastion/${name}.nft".text = ruleset;
}
