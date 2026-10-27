# Bastion

The NixOS configuration of a host named Bastion, its bastion tool, and the Windows presets its VMs run, without the values of any one machine.

## 1. First setup of a machine

On the machine, with NixOS installed. REPO is this repository's address; PRIVATE is the folder of the machine's private clone.

1. Clone this repository as the machine's private clone:

   ```
   git clone REPO bastion-configured-private
   ```

2. In bastion-configured-private, make the machine's files from the examples:
   - Copy nixos/local.example.nix to nixos/local.nix.
   - Write the machine's one normal user in place of USER.
   - Make the host's key for the Wi-Fi VM:

     ```
     sudo ssh-keygen -t ed25519 -f /root/.ssh/wifi-vm
     ```

   - Write the line of /root/.ssh/wifi-vm.pub in place of HOSTKEY.
   - Copy nixos/hosts/example/ to nixos/hosts/bastion/.
   - Write the machine's values in place of BOARD, TIMEZONE, LOCALE, KEYMAP, COUNTRY and the zeros of vfio-pci.ids.
   - Put the hardware-configuration.nix that nixos-generate-config wrote at the install into nixos/hosts/bastion/.
   - Add to nixos/hosts/bastion/ what the machine's disks and install need: mount options, the folders of the VM disks, its swap, its system.stateVersion.
   - Copy nixos/modules/isolation/stations.example.nix to stations.nix beside it, and write the machine's stations.
   - Keep the entry without a mac (the host) and the entries tpl-win10 and tpl-win11 (bastion template reads their mac).
   - Copy nixos/modules/isolation/uplinks.example.nix to uplinks.nix beside it, and write the machine's cards.
   - The card values are read from /sys/bus/pci/devices and /sys/bus/usb/devices.
   - Copy presets/sync/sync.conf.example to presets/sync/sync.conf: one line per host, as its first line says.
3. Commit them in the private clone only. .gitignore lists them, so they are added with -f:

   ```
   git add -f nixos/local.nix nixos/hosts/bastion/ nixos/modules/isolation/stations.nix nixos/modules/isolation/uplinks.nix presets/sync/sync.conf
   git commit -m "<what changed>"
   ```

4. Replace the files of /etc/nixos with the private clone's nixos/, keeping /etc/nixos/.git. On a new machine, make that repository first with `sudo git init /etc/nixos`. The first commit keeps what was there; it may say nothing to commit:

   ```
   sudo git -C /etc/nixos add -A
   sudo git -C /etc/nixos commit -m "before the update"
   sudo find /etc/nixos -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
   sudo cp -r PRIVATE/nixos/. /etc/nixos/
   ```

5. Add every file to /etc/nixos's own repository:

   ```
   sudo git -C /etc/nixos add -A
   ```

6. Build the system the next start boots:

   ```
   sudo nixos-rebuild boot --flake /etc/nixos#bastion
   ```

7. Restart:

   ```
   reboot
   ```

8. Copy the private clone's presets/ over ~/presets. Files already there that the clone does not hold, such as the downloaded installers and the VM copies in ~/presets/bastion, stay:

   ```
   mkdir -p ~/presets
   cp -r PRIVATE/presets/. ~/presets/
   chmod +x ~/presets/attach.sh ~/presets/sync/sync.sh
   ```

## 2. Updating

1. In the private clone (--rebase keeps the machine's own commit on top of this repository's new commits):

   ```
   git pull --rebase
   ```

2. Do steps 4 to 8 of the first setup.

## 3. The bastion tool

Open the status screen:

```
bastion
```

Keys of the status screen:

- v: VMs
- n: networks
- d: devices
- l: looking-glass
- b: the broker (the file exchange)
- r: read again
- q: quit

In every other screen, escape goes back. In every section, r reads again.
On a screen of several picks: space or Enter picks and unpicks, ctrl+s goes on.
On a summary screen: Enter goes on.

### v: VMs

- The table: name, state, cores, RAM, disk, graphics, network, internet rule.
- n: new VM (section 4).
- copy firmware and TPM: each VM's firmware variables and TPM state into ~/presets/bastion/state; a running VM is skipped.
- restore: the VMs saved in ~/presets/bastion that are not defined now, definitions only or whole.
- A VM's row opens its screen, with these actions:
  - start
  - first start (no network for that start)
  - shut down
  - open its window
  - console
  - cores, fast cores first, RAM, graphics: take effect at the VM's next start
  - disk: bigger only, never smaller
  - internet rule: open, listed or none; takes effect at once
  - retire: its disk, definition, firmware variables and TPM state move into /var/lib/libvirt/images/retired/NAME; nothing is deleted

### n: networks

- A network's line: VMs reach each other, yes or no.
- A VM's line: internet rule, move to a network, path check.
- new network.

### d: devices

- The host's graphics devices.

### l: looking-glass

- A VM's line (a VM with a card): glass on or off; resolution, follows the window or locked at a size.
- release key, full screen: the looking-glass window's settings.

### b: the broker

- See section 6.

### The command line

- `bastion`: the status screen, then the VMs, the networks, the devices, looking-glass and the broker.
- `bastion list`: every VM and template, its state, its disk, its card.
- `bastion template T`: Windows Setup in the template tpl-T (T: win10 or win11).
- `bastion seal T`: after Sysprep: tpl-T sealed, bastion makes VMs from it.
- `bastion first NAME`: the first start of NAME, without network.
- `bastion start NAME`: starts NAME and shows it.
- `bastion console NAME`: the console window of NAME.
- `bastion resolution NAME`: the size NAME's Windows is locked at, or follows.
- `bastion exchange-files DIR`: the files the presets module exchange sets the exchange up with, into DIR/exchange.
- `bastion virtio-files DIR`: the virtio driver folders the presets module repair installs, into DIR/virtio.
- `bastion send FROM FILE TO`: one file from FROM's Outbox to TO's Inbox, or to the host's inbox when TO is the host's name.
- `bastion transfers [NAME]`: broker-vm's log, all of it or the lines naming NAME.
- `bastion clean NAME`: NAME's kept copies in broker-vm deleted, and the files of NAME's stopped sends on the host, each logged first.

template, first and start run until the VM is off; meanwhile the host does not go to sleep by itself. Never close the lid then.

## 4. A Windows VM from nothing to running

T is win10 or win11.

1. Download the Windows .iso into ~/Downloads. Its name holds windows_10 for win10, windows_11 for win11; only one such .iso.
2. Start Windows Setup in the template:

   ```
   bastion template T
   ```

   It copies the .iso in place (the download is removed), defines tpl-T, opens its console, starts it with Space pressed for the CD prompt, and waits until it is off.
3. In the console, install Windows.
4. Run Sysprep in it. tpl-T must end shut off.
5. Seal the template:

   ```
   bastion seal T
   ```

   It checks that tpl-T is shut off with Windows installed, marks it sealed, and undefines it, keeping its firmware variables and TPM state.
6. Make a VM from it:

   ```
   bastion
   ```

   Press v, then n, and answer: 1. Name, 2. Windows (T), 3. Cores, 3b. Fast cores first?, 4. RAM, 5. Disk, 6. Graphics, 7. Network, Internet.
   At 8, the summary, press Enter: make it.
7. The first start, without network: v, the VM, first start (no network for that start), Enter: start it. Or:

   ```
   bastion first NAME
   ```

   Its console opens. The offline first-boot screens are done by hand.
8. Every later start: v, the VM, start, Enter: start it. Or:

   ```
   bastion start NAME
   ```

   The looking-glass window opens for a VM with glass on, the console otherwise.
   Never close the lid while it runs. Shut Windows down to end it.
9. The console of any VM: v, the VM, console. Or:

   ```
   bastion console NAME
   ```

## 5. Attach and run the presets

1. Start the VM (section 4).
2. On the host, build the PRESETS stick from ~/presets/win and plug it into the VM:

   ```
   ~/presets/attach.sh NAME
   ```

   Without NAME it shows a numbered list of the VMs: type the number.
3. In Windows, open the PRESETS drive and run win\run.cmd (it asks for admin itself):
   - `run.cmd`: every module in order.
   - `run.cmd firefox`: only the firefox module.
   - `run.cmd debloat updates`: only those two.
   - `run.cmd repair`: only on this word, never in a run without words. It reinstalls the virtio drivers of that Windows from the stick (viostor for the disk, NetKVM for the network card, qxldod for the QXL video on Windows 10; no internet needed), each installer of assets/installers.json that is on the stick whatever version is installed, and nvidia-app.exe when it is there. Looking Glass is not touched. Run it after `attach.sh NAME` has built the stick for that VM.
   - A driver goes onto a device only when no driver ranked as high is on it: a device whose driver was deleted gets it, a device on the same driver keeps it.
4. When done, unplug the stick on the host:

   ```
   virsh -c qemu:///system detach-disk NAME sdz --live
   ```

The module words: shell, copy-path, context-menu, defender, edge, ie, debloat, updates, activation, grow-c, installers, firefox, nvidia, lg-host, resolution, exchange, and repair, which runs only by `run.cmd repair`.
The run.cmd window stays open at the end. The full log, with each module's end (done, skipped, waits for restart or failed): C:\ProgramData\Bastion\setup.log; before the silent Looking Glass install (lg-host) it says "[lg-host] Looking Glass requires cumulative updates from Windows, otherwise it will not work at all.", and the display driver starts after the restart that follows.
Whenever a restart is pending at the run's end, it asks `Restart Windows now to finish this setup? (y/n)`: y restarts Windows at once; n leaves the restart to you.
A module that needs a restart first ends "waits for restart" (lg-host after a driver install). At the next sign-in of an account of the Administrators group after the restart, Windows starts run.cmd from the PRESETS stick by itself, with the words of the modules that waited alone; it asks for administrator rights once.
A sign-in of an account outside Administrators starts nothing: it waits for an administrator's sign-in.
When the stick was unplugged before the restart, run `~/presets/attach.sh NAME` on the host again, then in Windows run.cmd with the module's word, such as `run.cmd lg-host`.
The updates step installs the updates Windows Update offers that Windows, downloaded from Microsoft: it needs the VM's internet and may take long; the log shows each update's title, size and result. Without internet the log says FAILED: in bastion set the VM's internet rule to open (v, the VM, internet rule), then run run.cmd updates.
The activation step asks for the Windows product key at the console: the key is typed and kept nowhere, not in the log. An activated Windows is skipped and asked nothing; Enter skips the step, and run.cmd activation asks again. It needs the VM's internet: without it the log says FAILED: in bastion set the VM's internet rule to open (v, the VM, internet rule), then run run.cmd activation.

Files placed by hand in ~/presets/win/assets, under these exact names:

- roots.p7b: the CA bundle. Download https://curl.se/ca/cacert.pem, then:

  ```
  openssl crl2pkcs7 -nocrl -certfile cacert.pem -outform DER -out roots.p7b
  ```

- nvidia-app.exe: only on the VM that should have the NVIDIA app.

An absent file skips its install step. attach.sh brings the other installers itself.

## 6. The file exchange

Routes, in bastion: b, the VM's line, sends to; pick the VMs and the host it may send to; ctrl+s saves.

Each VM's setup, once:

1. Start it with bastion start NAME. A VM started outside bastion has no exchange device.
2. On the host:

   ```
   ~/presets/attach.sh NAME
   ```

3. In Windows, from the PRESETS drive's win folder:

   ```
   run.cmd exchange
   ```

A VM without internet needs it for run.cmd exchange, for run.cmd updates and for run.cmd activation: in bastion set its internet rule to open (v, the VM, internet rule), run run.cmd exchange, run.cmd updates or run.cmd activation in the VM, then set the rule back the same way.

In Windows, a file to send goes into C:\Exchange\Outbox; a file sent to the VM arrives in C:\Exchange\Inbox.
The host's inbox is /var/lib/exchange/inbox.

Send one file (TO: a VM, or the host's name, its entry without a mac in stations.nix):

```
bastion send FROM FILE TO
```

Or in bastion: b, the VM, send a file, the file, the destination.
Or b, send a file, the VM, the file, the destination.

Transfers, broker-vm's log, all of it or the lines naming NAME:

```
bastion transfers
bastion transfers NAME
```

Or b, transfers; or b, the VM, transfers.

Clean NAME's kept copies in broker-vm, and the files of NAME's stopped sends on the host:

```
bastion clean NAME
```

Or b, the VM, clean its kept copies, then clean its kept copies again.

## 7. gate on the host

UPLINK is an entry of uplinks.nix (wifi and ethernet in the example).

- `gate status`: wifi-vm, firewall-vm, broker-vm, the switches and their cables, the uplinks and the way out, seen from the host.
- `gate UPLINK`, for the uplink of kind "vm": wifi-vm's Wi-Fi screen (nmtui), then allow UPLINK: it may carry the host's route and DNS.
- `gate UPLINK`, for an uplink of kind "ethernet": allow UPLINK: it may carry the host's route and DNS, by itself whenever plugged in.
- `gate UPLINK off`: withdraw UPLINK: no route or DNS of the host over it; its link stays up.
- `gate prefer UPLINK`: UPLINK carries the traffic when more than one is allowed and up.
- `gate log [NAME]`: firewall-vm's log of NAME (or of all): names asked, connections made and refused.
- `gate`: this list.

## 8. The private files

They stand only in the machine's private clone.

| Private file | Made from |
|---|---|
| nixos/local.nix | nixos/local.example.nix |
| nixos/hosts/bastion/ | nixos/hosts/example/ |
| nixos/modules/isolation/stations.nix | nixos/modules/isolation/stations.example.nix |
| nixos/modules/isolation/uplinks.nix | nixos/modules/isolation/uplinks.example.nix |
| presets/sync/sync.conf | presets/sync/sync.conf.example |
| presets/win/assets/roots.p7b | the openssl line in section 5 |
| presets/win/assets/looking-glass-host.exe | brought by attach.sh |
