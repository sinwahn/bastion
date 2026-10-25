BASTION SYNC - THE HOST AND THE OTHER MACHINE
=============================================

WHAT THIS IS
  One script, sync.sh, that makes one machine equal to the other:
    - after one command on the host, /etc/nixos and ~/presets equal the
      other machine;
    - after one command on the other machine, it equals the host.
  Every transferred file is checked by SHA-256 when it arrives, and the
  presets files once more after they are put in place. The host's
  nixos-rebuild runs only when you press Enter for it.

  What travels is one file, bastion-sync-<UTC>.tar (<UTC> is the time it
  was made, for example 20000101T000000Z). Inside it:
    nixos.bundle   the whole nixos git repository (every branch, every
                   commit)
    presets.tar    every file of the presets folder, except presets.img,
                   _archive/presets.img, sync/incoming/ and bastion/state/
    MANIFEST       the machine, the time, the nixos commit and branch, the
                   number of presets files
    SHA256SUMS     the SHA-256 of each of the above and of every presets
                   file

FILES
  sync.sh      the script, two commands:
                 sync.sh pack <out-dir>    makes the .tar in <out-dir>
                 sync.sh unpack <tar>      takes a .tar in
  sync.conf    one line per machine, picked by its name (plain hostname,
               cut at the first dot): where its nixos repository and its
               presets folder are,
               whether the nixos folder needs sudo, and the flake name to
               rebuild (bastion on the host, no on the other machine).
  README.txt   this file.

THE FIRST TIME, BY HAND
  The host has no sync folder yet. Copy this folder once, as it is
  (sync.sh, sync.conf, README.txt), to ~/presets/sync/ on the host.
  After that every unpack on the host brings the newest sync folder
  along with the other presets files.

THE OTHER MACHINE TO THE HOST (the host becomes equal to the other machine)
  On the other machine, MIRROR being the folder that holds its nixos and
  presets folders (its sync.conf line):
  1. Commit the nixos changes in MIRROR/nixos (pack
     refuses a working tree with changes).
  2. Make the archive in a folder of your choice, OUT:
       bash MIRROR/presets/sync/sync.sh pack OUT
     Ends with: ALL OK. The archive: OUT/bastion-sync-<UTC>.tar
  3. Carry that one .tar file to the host.
  On the host:
  4. Put the .tar into ~/presets/sync/incoming/ (the first time:
       mkdir -p ~/presets/sync/incoming ).
  5. Unpack it:
       bash ~/presets/sync/sync.sh unpack ~/presets/sync/incoming/bastion-sync-<UTC>.tar
     It checks every hash, then shows the commits that come in, the nixos
     files that change, and the presets files that are added or changed.
     Nothing is changed yet.
  6. Read that. Press Enter to apply, or Ctrl-C to stop (nothing changed).
     /etc/nixos moves forward to the other machine's commit; the presets files
     are copied in and checked again by hash.
  7. It asks: Press Enter to run nixos-rebuild switch. Enter rebuilds;
     Ctrl-C leaves the running system as it is.
     Ends with: ALL OK.

THE HOST TO THE OTHER MACHINE (the other machine becomes equal to the host)
  On the host:
  1. Commit your nixos changes:
       sudo git -C /etc/nixos add -A
       sudo git -C /etc/nixos commit -m "<what changed>"
  2. Make the archive:
       bash ~/presets/sync/sync.sh pack OUT
     Ends with: ALL OK. The archive: OUT/bastion-sync-<UTC>.tar
  3. Carry that .tar file to the other machine.
  On the other machine:
  4. Put it into MIRROR/presets/sync/incoming/.
  5. Unpack it:
       bash MIRROR/presets/sync/sync.sh unpack MIRROR/presets/sync/incoming/bastion-sync-<UTC>.tar
  6. Read what it shows; Enter applies. The other machine never rebuilds
     (rebuild=no in sync.conf).

WHAT IT REFUSES, AND WHY
  pack refuses (exit 1, nothing packed):
    - a nixos working tree with any change; it prints git status. Only
      commits travel, so an uncommitted change would be left behind.
    - a tracked nixos file that contains a CR byte; it lists them. Windows
      line endings must never reach /etc/nixos.
    - a missing nixos folder or presets folder.
  unpack stops (exit 1):
    - before anything is changed: a hash that does not match, a bundle
      that git bundle verify rejects, a presets file that does not match
      its hash. The archive was damaged on the way; make it again.
    - after Enter, before anything is changed: a modified file in the
      nixos folder whose content differs from the incoming commit's; it
      lists them. Your local change would be lost; commit it or move it
      first. A modified file that is already exactly the incoming content
      is taken as it is.
    - when the nixos branch cannot move forward to the incoming one (git
      merge --ff-only fails, for example both machines made different
      commits). It prints git's message; the presets are not touched.
  Nothing is ever deleted: a presets file that exists only on the
  receiving machine stays.

WHERE INCOMING ARCHIVES STAY
  <presets>/sync/incoming/ holds each .tar you put there and, beside it,
  the folder <UTC>/ that unpack made from it:
    nixos.bundle, presets.tar, MANIFEST, SHA256SUMS   from the archive
    presets/     the presets files as they came in
    log.txt      every line unpack printed (each run on that archive adds
                 to it)
  The script deletes nothing there. pack never puts sync/incoming/ into a
  new archive.
