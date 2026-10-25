BASTION WINDOWS SETUP (modular)
===============================

One elevated launcher runs small, independent, idempotent modules. Re-run the
whole thing or just one module at any time - safe to repeat. If Microsoft or an
update changes something back later, re-run the matching module.

HOW TO RUN (inside the Windows workstation, from the PRESETS drive):
  run.cmd: run every module in order (asks for admin itself)
  run.cmd firefox: run only the firefox module
  run.cmd debloat updates: run just those
The window stays open at the end. Full log: C:\ProgramData\Bastion\setup.log
(THE LOG below says what each line means). When the administrator rights are
not given, the window says so and waits for a key; nothing runs then.
A VM without internet needs it once for run.cmd exchange, which adds Windows'
OpenSSH Server: on the host, set the VM's internet rule to open in bastion
(v, the VM, internet rule); in the VM, run.cmd exchange; then set the rule
back the same way. No rebuild.

LAYOUT:
  run.cmd: self-elevating launcher (double-click this)
  run.ps1: the runner it calls
  lib\common.ps1: shared helpers (not run on its own)
  modules\: one component per file, run in numeric order:
     10-shell: Explorer prefs, dark mode, This PC nodes, Spotlight off, search box off
     15-copy-path: "Copy full path" right-click entry
     20-context-menu: strip Send to / Share / Give access / Cast / etc.
     30-defender: Defender scanning off (firewall + UAC stay)
     40-edge: remove Microsoft Edge
     45-ie: remove Internet Explorer
     50-debloat: consumer features off, Dev Home removed, Windows Backup shortcut removed
     60-updates: no automatic Windows Update, no surprise reboots
     70-grow-c: extend C: to fill the disk
     75-installers: install each installer in assets\installers.json that is missing or older, asking first where the list says so (System Informer)
     80-firefox: Firefox certs + AutoConfig prefs + uBlock/Dark Reader
     90-nvidia: install the NVIDIA app silently if present (the driver comes from 75-installers)
     95-lg-host: install the Looking Glass host in its own installer window, only in a boot with no restart pending (see LOOKING GLASS below)
     96-resolution: lock the Looking Glass display at the size in resolution.txt, or let it follow the window
     97-exchange: the exchange of files between the VMs: the vsock driver, vstbridge, OpenSSH Server, the account exchange (only the host's key logs into it, SFTP only), C:\Exchange with Inbox and Outbox; ends at once in a VM with no exchange device (started outside bastion, or a template)
  assets\: the installers; attach.sh keeps the listed ones current and brings looking-glass-host.exe, the others are put here by hand (see below)
  resolution.txt: on the stick only, written by attach.sh for the VM it plugs into
  exchange\: on the stick only, written by attach.sh from bastion exchange-files: the driver files, the host's public key and exchange.json for 97-exchange

ASSETS in assets\ (these exact names):
  attach.sh keeps these current, as listed in assets\installers.json:
  firefox-setup.exe: Firefox installer (full, not the stub)
  nvidia-driver.exe: NVIDIA Game Ready driver (driver-only install)
  system-informer-setup.exe: System Informer installer
  attach.sh brings this one at the build looking-glass.nix pins:
  looking-glass-host.exe: Looking Glass host, brought by attach.sh at the build looking-glass.nix pins
  you drop these in by hand, renamed to these exact names:
  roots.p7b: the CA bundle (README.md says how to make it)
  nvidia-app.exe: ONLY on the VM that should have the NVIDIA app - adds the NVIDIA app on top of the driver
Any asset that is absent just skips its install step; nothing errors.

THE LOG, C:\ProgramData\Bastion\setup.log:
Every line the run shows also goes to setup.log, after its date and time. A
second run adds its lines below the first one's. When setup.log cannot be
written, the window says "setup.log could not be written:" and the reason,
once per run.
- "==== run start" with the date and time: a run begins. Then "Windows:" with
Windows' name, version and build, "elevated: yes" or "elevated: no", the
presets folder, and the modules to run.
- "start NAME" and "end NAME: done", "end NAME: skipped" or "end NAME:
failed" (with the error): each module's beginning and end.
- "[word] ...": what a module does, what it skips and why, and what fails;
every failure line holds the word FAILED and Windows' own message.
- "run: PROGRAM ARGUMENTS", then "exit N (0x...)": a console program (reg,
diskpart, nvidia-smi, certutil, pnputil, icacls, vstbridge) and its exit
code. For a code other than 0 the line is "FAILED, exit N (0x...)", followed
by each line the program printed, as "output: ...".
- "start: INSTALLER ARGUMENTS", then "exit N (0x...)" or "FAILED, exit N
(0x...)": an installer, started in its own window as always, and its exit
code. A program that cannot be started: "FAILED, could not start ...".
- "restart pending: ...": which restart mark or Windows value makes Looking
Glass wait for a restart.
- "summary: NAME done", "skipped" or "failed": one line per module at the
end, then "Restart Windows to finish this setup." when a module asks for it.

LOOKING GLASS (95-lg-host):
It installs only in a boot with no restart pending. After a driver install
(75-installers sets the restart mark) or while Windows itself reports a
pending restart, it installs nothing and says "[lg-host] a restart is
pending: restart Windows, then run.cmd lg-host". Otherwise it opens the
installer's own window, as a double-click does: click through it to its
end. setup.log then says "[lg-host] installed" or "[lg-host] install
FAILED, exit N (0x...)".
A VM where the Looking Glass install crashed (setup.log says "installer exit
-1073741819" or "[lg-host] install FAILED"):
1. In Windows' installed apps (Settings, Apps), uninstall "Looking Glass (IDD)".
2. Restart Windows.
3. Run run.cmd lg-host and click through the installer's window.

NOTES:
  - Default browser cannot be set by a script on Windows 10 (the choice is hash-
    protected). Set Firefox default once in Settings > Apps > Default apps, or
    apply a default-associations file in the template.
  - NVIDIA driver-only means no auto driver updates inside Windows. attach.sh keeps
    the installers listed in assets\installers.json current, and the run installs
    each only when it is missing or older than the one on the stick:
    run.cmd installers
  - NVIDIA documents only the -s and -n switches of its driver installer; the
    driver keeps -s -noreboot -clean.
  - Still manual per VM, by design: the offline first-boot screens, your Windows
    product key (typed only into the activation box), and the final resolution/scaling.
