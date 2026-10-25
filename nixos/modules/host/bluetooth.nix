# /etc/nixos/modules/host/bluetooth.nix
# Bluetooth stays on the host. On a card that is Wi-Fi and Bluetooth in one,
# only the Wi-Fi PCIe function is passed to the Wi-Fi VM, so the Bluetooth
# USB side remains on the host. PipeWire carries Bluetooth audio once bluez
# is enabled, so the guest's game audio - which arrives on the host through
# Looking Glass - plays on Bluetooth headphones simply by making them the
# host's default sink. Pair with the Plasma applet or bluetoothctl.
{ ... }:
{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Report headset battery level where the device supports it.
  hardware.bluetooth.settings.General.Experimental = true;
}
