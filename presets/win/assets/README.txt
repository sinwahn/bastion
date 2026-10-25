attach.sh keeps these current at every attach, as listed in installers.json:
  nvidia-driver.exe: NVIDIA Game Ready driver
  firefox-setup.exe: Firefox full installer
  system-informer-setup.exe: System Informer installer
  The version of each stands beside it in <file name>.version.
  NVIDIA documents no interface for its current driver; attach.sh reads the host's NVIDIA card, asks NVIDIA's own driver lookup for that card and keeps only a package that lists the card.
attach.sh brings this one at the build looking-glass.nix pins:
  looking-glass-host.exe: Looking Glass host, brought by attach.sh at the build looking-glass.nix pins
Put these here by hand, renamed exactly:
  roots.p7b: CA bundle
  nvidia-app.exe: optional, only on the VM that should have the NVIDIA app
Absent files are skipped, not errors.
