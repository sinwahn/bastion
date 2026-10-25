{
  # user: the name of the one normal user of this machine, the account made when NixOS was installed on it.
  user = "USER";
  # hostKey: the line of /root/.ssh/<the Wi-Fi VM's name>.pub; on a new machine, sudo ssh-keygen -t ed25519 -f /root/.ssh/<the Wi-Fi VM's name> makes that key.
  hostKey = "HOSTKEY";
}
