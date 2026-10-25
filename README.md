# Bastion

## What this is

The NixOS configuration of a host named Bastion and the Windows presets its VMs run, without the values of any one machine.

- nixos/ is the NixOS configuration: a flake whose nixosConfigurations.bastion is the host, with its microVMs and its workstations.
- presets/ holds what the Windows workstations run: the Windows setup in presets/win, attach.sh, which builds the presets disk from presets/win for a workstation, and presets/sync, which makes the configuration and the presets of one machine equal to another's.

This repository holds no value of a machine: no user name, key or disk id, no model or id of its hardware, no name, MAC or address of its VMs, no time zone or place. A machine's own configuration is a private clone of this repository with that machine's files added and committed there (below). This repository alone does not build: the flake imports files that stand only in a machine's private clone.

## Layout

- nixos/flake.nix, nixos/flake.lock: the flake and its pinned inputs.
- nixos/local.example.nix: the example of nixos/local.nix (below).
- nixos/hosts/example/: the example of a machine's own folder, nixos/hosts/bastion/ (below).
- nixos/modules/host/: the host itself, one file per subject (boot, networking, desktop, users, virtualization, VFIO, Looking Glass and others).
- nixos/modules/isolation/: the microVMs and their networks; net.nix is the Wi-Fi VM; stations.example.nix and uplinks.example.nix are the examples of stations.nix and uplinks.nix (below).
- nixos/modules/bastion/: the bastion tool.
- presets/attach.sh: builds the presets disk for a workstation and keeps the downloaded installers current.
- presets/win/: the Windows setup; presets/win/README.txt says how it runs.
- presets/sync/: sync.sh, which carries the nixos repository and the presets between two machines; presets/sync/README.txt has the steps.

## A machine's private clone

A machine's own configuration is a git clone of this repository, kept by the machine's owner and never published, with the machine's files added and committed in it. Its nixos/ folder is what is copied to /etc/nixos (below). .gitignore lists the machine's files, so they are never added to this repository; in the private clone they are added once with git add -f and committed:

- nixos/local.nix: the user name of the machine's one normal user, and hostKey, the public half of the key the host uses for the Wi-Fi VM. Its example is nixos/local.example.nix: copy it to nixos/local.nix and write the two values in place of USER and HOSTKEY, as its comment lines say. The flake hands it to every module as local.
- nixos/hosts/bastion/: the machine's own folder; the flake imports its default.nix. It holds the hardware scan, hardware-configuration.nix, which nixos-generate-config writes when NixOS is installed (the disk ids among it), and default.nix, which imports the hardware scan, the machine's board module of nixos-hardware and any module of that machine alone, and sets the time zone, locale and keyboard, the ids of the card a VM takes and the country of the Wi-Fi radio rules. Its example is nixos/hosts/example/: copy it to nixos/hosts/bastion/ and write the machine's values in place of the words in capitals.
- nixos/modules/isolation/stations.nix: every machine behind the firewall VM, with its address, its MAC and its internet rule. Its example is nixos/modules/isolation/stations.example.nix.
- nixos/modules/isolation/uplinks.nix: the host's uplinks, with the PCI address and drivers of its Wi-Fi card and the USB ids of its ethernet card. Its example is nixos/modules/isolation/uplinks.example.nix.
- presets/sync/sync.conf: one line per machine for sync.sh. Its example is presets/sync/sync.conf.example: copy it to presets/sync/sync.conf; on its mirror line, write the other machine's host name in place of mirror and the folder that holds its nixos and presets folders in place of MIRROR.
- presets/win/assets/roots.p7b and presets/win/assets/looking-glass-host.exe: the CA bundle and the Looking Glass host installer (below).

The private clone's own commits change only these files, which this repository does not hold, so taking this repository's updates never meets a change of the same lines.

### Taking this repository's updates

In the private clone, git pull takes this repository's new commits. A plain git pull only fast-forwards (git pull's default) and stops in the private clone, whose own commit this repository does not hold; so it is run with --rebase, which puts the machine's own commit back on top of this repository's new commits:

    git pull --rebase

git pull --no-rebase merges them instead.

## Files placed by hand in presets/win/assets

attach.sh brings the installers listed in presets/win/assets/installers.json and the Looking Glass host installer. These are placed by hand, under these exact names, as presets/win/README.txt lists them:

- roots.p7b: the CA bundle (below).
- nvidia-app.exe: only on the VM that should have the NVIDIA app; adds the NVIDIA app on top of the driver.

None of them is committed in this repository; roots.p7b and looking-glass-host.exe are committed in the private clone. An asset that is absent skips its install step.

## roots.p7b

roots.p7b is a PKCS#7 bundle of root certificates. presets/win/modules/80-firefox.ps1 imports it into Windows' Root and CA stores.

It is there because a Windows without internet at its first start lacks these root certificates, so the automatic Firefox installation met certificate errors.

A machine makes its copy from Mozilla's list of root certificates as curl publishes it:

1. Download cacert.pem from https://curl.se/ca/cacert.pem (curl's page https://curl.se/docs/caextract.html: "The Mozilla CA certificate store in PEM format").
2. Turn it into a PKCS#7 file in DER form (https://docs.openssl.org/3.5/man1/openssl-crl2pkcs7/: -nocrl, -certfile, -outform DER, -out):

       openssl crl2pkcs7 -nocrl -certfile cacert.pem -outform DER -out roots.p7b

3. Place roots.p7b in presets/win/assets of the private clone.

## Applying it on the host

1. Copy the files of the private clone's nixos/ over /etc/nixos, as root. /etc/nixos keeps its own .git.
2. Add every file to /etc/nixos's own repository, which stays on the host:

       sudo git -C /etc/nixos add -A

3. Build the new system as the one the next start boots:

       sudo nixos-rebuild boot --flake /etc/nixos#bastion

4. Restart:

       reboot
