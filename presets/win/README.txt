BASTION WINDOWS SETUP (modular)
===============================

One elevated launcher runs small, independent, idempotent modules. Re-run the
whole thing or just one module at any time - safe to repeat. If Microsoft or an
update changes something back later, re-run the matching module.

HOW TO RUN (inside the Windows workstation, from the PRESETS drive):
  run.cmd: run every module in order (asks for admin itself)
  run.cmd firefox: run only the firefox module
  run.cmd debloat updates: run just those
  run.cmd repair: only on this word, never in a run without words: reinstalls
    the virtio drivers of this Windows from the stick's win\virtio (no internet
    needed), each installer of assets\installers.json that is on the stick,
    whatever version is installed (asking first where the list says so), and
    assets\nvidia-app.exe when it is there; Looking Glass is not touched. Run it
    after attach.sh NAME has built the stick for this VM.
    A driver goes onto a device only when no driver ranked as high is on it: a device whose driver was deleted gets it, a device on the same driver keeps it.
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
     60-updates: installs the updates Windows Update offers this Windows (downloaded from Microsoft: needs the VM's internet, may take long; without it, open the VM's internet rule, then run.cmd updates), then no automatic Windows Update, no surprise reboots
     70-grow-c: extend C: to fill the disk
     75-installers: install each installer in assets\installers.json that is missing or older, asking first where the list says so (System Informer)
     80-firefox: Firefox certs + AutoConfig prefs + uBlock/Dark Reader
     90-nvidia: install the NVIDIA app silently if present (the driver comes from 75-installers)
     95-lg-host: install the Looking Glass host silently, no window to click through, only in a boot with no restart pending; it needs Windows' cumulative updates, and its display driver starts after a restart (see LOOKING GLASS below)
     96-resolution: lock the Looking Glass display at the size in resolution.txt, or let it follow the window
     97-exchange: the exchange of files between the VMs: the vsock driver, vstbridge, OpenSSH Server, the account exchange (only the host's key logs into it, SFTP only), C:\Exchange with Inbox and Outbox; ends at once in a VM with no exchange device (started outside bastion, or a template)
     99-repair: only by run.cmd repair: the virtio drivers from virtio\ (viostor for the disk, NetKVM for the network card, qxldod for the QXL video, which the virtio ISO holds for Windows 10 alone), the installers on the stick and the NVIDIA app, reinstalled
  assets\: the installers; attach.sh keeps the listed ones current and brings looking-glass-host.exe, the others are put here by hand (see below)
  resolution.txt: on the stick only, written by attach.sh for the VM it plugs into
  exchange\: on the stick only, written by attach.sh from bastion exchange-files: the driver files, the host's public key and exchange.json for 97-exchange
  virtio\: on the stick only, written by attach.sh from bastion virtio-files: the virtio driver folders for 99-repair

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
by each line the program printed, as "output: ...". In 99-repair pnputil's
0, 259 and 3010 count as success: "exit N (0x...)" is followed by the code's
meaning.
- "start: INSTALLER ARGUMENTS", then "exit N (0x...)" or "FAILED, exit N
(0x...)": an installer, started in its own window as always, and its exit
code. A program that cannot be started: "FAILED, could not start ...".
- "[updates] ...": 60-updates installs the updates Windows Update offers this
Windows, downloaded from Microsoft; it needs the VM's internet and may take
long, as its first line says. Before the download: each update's title and
its size, "up to N MB". An update that can ask for input is skipped; for an
update with a license, its text is shown and "accept the license of TITLE?
(y/n)" asked, n skips it; the license text and that question show on the
screen only and are not in setup.log, an exception to the first sentence of
THE LOG; the answer is in setup.log. An update that fails to download gets a
line of its own: "TITLE: not downloaded, download result N NAME", with FAILED
and the HResult for 4 and 5, then "- not installed". An exclusive update is
installed in an Install call of its own. After the install: "TITLE: result N
NAME", 4 orcFailed and 5 orcAborted with FAILED and the HResult; "restart
mark set" names the update
that needs the restart. When Search, Download or Install fails: "FAILED", the
call, Windows' code and message, then the way: in bastion on the host, set
the VM's internet rule to open (v, the VM, internet rule), then run.cmd
updates.
- "restart pending: ...": which restart mark or Windows value makes Looking
Glass wait for a restart, or makes the run ask for a restart at its end.
- "[lg-host] Looking Glass requires cumulative updates from Windows,
otherwise it will not work at all.": stated before the Looking Glass
installer starts, no check made. Then "start: ...looking-glass-host.exe
/S", and "[lg-host] installed" with "[lg-host] restart mark set: the
display driver starts after the restart of Windows", or "[lg-host] install
FAILED, exit N (0x...)".
- "summary: NAME done", "skipped" or "failed": one line per module at the
end, then "Restart Windows to finish this setup." when a module asks for it.

LOOKING GLASS (95-lg-host):
It installs only in a boot with no restart pending. After a driver install
(75-installers sets the restart mark) or while Windows itself reports a
pending restart, it installs nothing, says "[lg-host] a restart is pending:
waits for restart; after it the run goes on with lg-host by itself" and
ends "waits for restart". The run asks at its end "Restart Windows now to
finish this setup? (y/n)": y restarts Windows at once; n leaves the restart
to you. At the next sign-in of an account of the Administrators group after
the restart, Windows starts run.cmd lg-host from the PRESETS stick by
itself; it asks for administrator rights once, then runs lg-host. A sign-in
of an account outside Administrators starts nothing: it waits for an
administrator's sign-in. When the stick was unplugged before the restart,
run attach.sh NAME on the host again, then run.cmd lg-host in Windows. In a
boot with no restart pending setup.log first says "[lg-host] Looking Glass
requires cumulative updates from Windows, otherwise it will not work at
all.", then the installer runs silently, with no window. setup.log then
says "[lg-host] install FAILED, exit N (0x...)", or "[lg-host] installed"
and "[lg-host] restart mark set: the display driver starts after the
restart of Windows"; the run then asks at its end for that restart, as
above.
A VM where the Looking Glass install crashed (setup.log says "installer exit
-1073741819" or "[lg-host] install FAILED"):
1. In Windows' installed apps (Settings, Apps), uninstall "Looking Glass (IDD)".
2. Restart Windows.
3. Run run.cmd lg-host; the installer runs silently, with no window.

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
