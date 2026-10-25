# /etc/nixos/modules/isolation/host-networks.nix
# The names of the host's own networks, what a service VM's stop means, the
# URL gate checks the internet with and the seconds it waits for it (gate
# status waits that long for wifi-vm's answer too), and the paths and words
# of the exchange of files between the VMs, each written once here. Not a
# module: host.nix, net.nix, gateway.nix, broker.nix and bastion.nix read
# it; bastion.nix hands the exchange group to the bastion tool and writes it
# as JSON under /etc, and the presets module of the exchange reads its
# share of it from the stick.
# Each key is the thing's role and never changes; its value is the name the
# thing carries now. A rename changes the value only, and a rebuild.
#   switches  the host's two bridges: the one the workstations, the firewall
#             VM and the host sit on; the one only between the firewall VM
#             and the Wi-Fi VM.
#   vms       the three service VMs (microVMs): the one that holds the Wi-Fi
#             card; the one that decides what each workstation may reach;
#             the one that owns the exchange of files between the VMs.
#   meanings  what it means when a service VM is not running, by its key in
#             vms; gate status and the bastion tool show it beside the VM.
#   cables    the service VMs' cables: the firewall VM's on the workstations'
#             switch; the firewall VM's toward the Wi-Fi VM; the Wi-Fi VM's
#             toward the firewall VM. Each with
#     name    its name on the host, the name of the tap microvm.nix makes
#             before its VM starts, and its qemu id;
#     switch  the switch it goes on, by its key in switches; networks-apply
#             (host.nix) puts it there.
#   wifi-card the Wi-Fi card inside the Wi-Fi VM: net.nix names it by its
#             driver (uplinks.nix), and the VM's saved Wi-Fi networks are
#             bound to this name.
#   internet  the URL gate status fetches for its line "internet: yes" or
#             "no"; the bastion tool reads the same, and firewall-check
#             (gateway.nix) fetches it inside firewall-vm for the path check.
#   internet-wait  the seconds gate status, the bastion tool and
#             firewall-check wait for an answer from internet; gate status
#             waits that long for wifi-vm's answer too, the path check that
#             long for wifi-check's and twice that for firewall-check's, and
#             networks-write (bastion.nix) that long for firewall-apply's.
#   networks.json  the live data file on the host: every network and every
#             station on it with its address and internet rule; networks-apply
#             (host.nix) writes it from stations.nix when it is missing and
#             builds the guard from it; firewall-vm and broker-vm read its
#             folder through a read-only share (gateway.nix, broker.nix).
#   exchange  the exchange of files between the VMs through broker-vm
#             (broker.nix):
#     staging   the host's folder for a file during its send;
#     inbox     the host's own inbox;
#     key       the host's key for the VMs' exchange accounts; its public
#               half goes into the folder of networks.json under the key's
#               file name and .pub;
#     sends-to  the key of a station's list of destinations in
#               networks.json;
#     section   the name of the bastion tool's section of the exchange, as
#               the status screen's keys line and the help name it;
#     section-key  the key that opens that section on the status screen;
#     sends-to-label  the label of a station's list of destinations in
#               that section;
#     none      what that section shows for an empty list;
#     retired   the mark that section puts after a listed name whose VM is
#               not defined now;
#     verbs     the commands of the broker's program;
#     log       the words of the program's journal lines, which bastion
#               transfers shows the owner;
#     reasons   the reason of each refusal; hash and delivery are the
#               exchange step's own (bastion.nix), the reasons of a send
#               stopped after the take: the hashes of the file on the host
#               and of the kept copy differ, or the delivery failed;
#     send      the bastion tool's command that sends one file from a VM's
#               Outbox to another VM's Inbox or to the host's inbox;
#     transfers the bastion tool's command that shows broker-vm's log, and
#               the action of the broker section that shows it;
#     clean     the bastion tool's command that deletes a VM's kept copies
#               in broker-vm, and the files of the VM's stopped sends on
#               the host, each logged first;
#     step      the bastion tool's step that runs as root (bastion.nix):
#               the sends, the Outbox listing, the log, the clean and the
#               figures of the kept copies;
#     send-action  the action of the broker section that sends a file;
#     clean-action  the action of the broker section that deletes a VM's
#               kept copies, and the files of its stopped sends on the host;
#     failed    the folder inside staging that keeps the files of the sends
#               stopped after the take, each sender's in a folder named
#               after the sender;
#     lines     the sentences the bastion tool prints for the exchange, each
#               a format whose fields in braces are the names they carry:
#               {from} the sender, {to} the destination, {vm} a VM, {file}
#               the file's name, {bytes} its size, {sha256} its hash,
#               {kept} the kept copy's path in broker-vm, {path} the
#               delivered file's path, {reason} broker-vm's reason,
#               {broker} broker-vm's name, {command} the bastion tool's
#               command, {module} the presets module's word, {clean} the
#               clean command's word, {used}, {size} and {limit} the kept
#               copies' bytes, their volume's size and the limit, in GB,
#               {percent} the limit's share of the size, {count} the number
#               of files deleted:
#       may     broker-vm allows the send;
#       taken   the file is taken from the sender, with its size and hash;
#       kept    where broker-vm keeps its copy;
#       delivered  where the file arrived;
#       refused  broker-vm refused the send; nothing was taken;
#       not-running  a VM of the send is not running;
#       outside  a VM of the send was started outside the bastion tool and
#               has no exchange device;
#       no-answer  a VM of the send does not answer on its exchange;
#       full    the kept copies reach the limit; nothing is taken;
#       usage   broker-vm's line in the broker section: its kept copies,
#               their volume's size and the limit;
#       cleaned  broker-vm's clean of a VM: its kept copies deleted, their
#               count and bytes;
#       failed-cleaned  the files of a VM's stopped sends deleted on the
#               host, when there was at least one;
#     exchange-files  the bastion tool's command that copies the files of
#               the exchange's setup inside Windows into a folder;
#               presets/attach.sh reads it from the JSON copy of this group
#               bastion.nix writes under /etc, and puts the folder onto the
#               PRESETS stick;
#     module    the presets module that sets the exchange up inside each
#               Windows VM: the part of its file name
#               presets/win/modules/97-exchange.ps1 after the number, the
#               word run.cmd runs it by, and the stick's folder win\ of its
#               files; a rename changes the module's file name too;
#     account   the local account in each Windows VM, which only the host's
#               key logs into, SFTP only;
#     folder    the exchange's folder in each Windows VM, the account's
#               chroot;
#     inbox-folder  the folder inside it where the files sent to the VM
#               arrive;
#     outbox-folder  the folder inside it the VM's files are sent from;
#     bridge-folder  where the module puts vstbridge.exe, the place its
#               README names;
#     module-lines  the sentences the module prints, each a format whose
#               fields in braces are the names they carry: {command} the
#               bastion tool's command, {module} the module's word,
#               {service} the bridge's service, {state} the word Windows
#               reports, {version} sshd.exe's version, {account} the
#               account, {folder} the folder, {inbox} and {outbox} the
#               whole paths of the two folders inside it:
#       no-device  the VM has no exchange device (a VM started outside the
#               tool, or a template); the module ends;
#       no-capability  OpenSSH Server could not be added; the module ends;
#       driver  the state of the vsock device;
#       bridge  the state of the bridge's service;
#       sshd    the state of sshd and its version;
#       account  the account;
#       folders  the three folders.
{
  "networks.json" = "/var/lib/bastion/networks.json";
  wifi-card = "wifi-card";
  internet = "https://cache.nixos.org/nix-cache-info";
  internet-wait = 15;
  switches = {
    workstations = "workstations";
    wifi-link = "wifi-link";
  };
  vms = {
    wifi-vm = "wifi-vm";
    firewall-vm = "firewall-vm";
    broker-vm = "broker-vm";
  };
  meanings = {
    wifi-vm = "there is no internet over Wi-Fi";
    firewall-vm = "the VMs have no way out, nor has the host over Wi-Fi";
    broker-vm = "no file can be sent between the VMs";
  };
  exchange = {
    staging = "/var/lib/exchange/staging";
    inbox = "/var/lib/exchange/inbox";
    key = "/root/.ssh/exchange";
    sends-to = "sends-to";
    section = "the broker";
    section-key = "b";
    sends-to-label = "sends to";
    none = "nothing";
    retired = "no VM now";
    verbs = {
      ask = "ask";
      take = "take";
      done = "done";
      clean = "clean";
      usage = "usage";
    };
    log = {
      refused = "refused";
      taken = "taken";
      delivered = "delivered";
      cleaned = "cleaned";
      from = "from";
      to = "to";
      name = "name";
      bytes = "bytes";
      sha256 = "sha256";
      reason = "reason";
    };
    reasons = {
      route = "the sender's list does not name the destination";
      full = "the kept copies would pass the limit";
      count = "the bytes read differ from the bytes announced";
      file = "the file name holds a slash or a newline, or is . or ..";
      station = "not a VM of networks.json";
      host = "the host only receives";
      command = "not a command of broker-vm";
      hash = "the hashes of the staging file and the kept copy differ";
      delivery = "the delivery failed";
    };
    send = "send";
    transfers = "transfers";
    clean = "clean";
    step = "exchange";
    send-action = "send a file";
    clean-action = "clean its kept copies";
    failed = "failed";
    lines = {
      may = "{broker}: {from} may send to {to}.";
      taken = "taken from {from}: {file}, {bytes} bytes, sha256 {sha256}";
      kept = "kept in {broker}: {kept}";
      delivered = "delivered: {to} {path}";
      refused = "REFUSED: {from} may not send to {to}: {reason}. Nothing was taken. Logged.";
      not-running = "STOP: {vm} is not running ({command} start {vm}).";
      outside = "STOP: {vm} was started outside {command}, so it has no exchange device now: shut it down and start it with {command} start {vm}.";
      no-answer = "STOP: {vm} does not answer on its exchange: run the presets module {module} in it (attach.sh {vm}, then run.cmd {module}).";
      full = "STOP: kept copies fill {percent} percent of {broker}'s {size}: {command} {clean} NAME.";
      usage = "{broker}: running; kept copies: {used} of {size}; sends are refused from {limit}";
      cleaned = "{broker}: {count} kept copies of {vm} deleted, {bytes} bytes, each logged first.";
      failed-cleaned = "the host: {count} files of {vm}'s stopped sends deleted, {bytes} bytes, each logged first.";
    };
    exchange-files = "exchange-files";
    module = "exchange";
    account = "exchange";
    folder = "C:\\Exchange";
    inbox-folder = "Inbox";
    outbox-folder = "Outbox";
    bridge-folder = "C:\\Program Files\\vstbridge";
    module-lines = {
      no-device = "no exchange device: start this VM with {command} start NAME";
      no-capability = "OpenSSH Server could not be added: this VM may have no internet. Set its internet rule to open in {command}, run run.cmd {module} again, then set the rule back.";
      driver = "viosock driver: {state}";
      bridge = "{service}: {state}";
      sshd = "sshd: {state}, version {version}";
      account = "account: {account}";
      folders = "folders: {folder}, {inbox}, {outbox}";
    };
  };
  cables = {
    firewall-vm = { name = "firewall-vm"; switch = "workstations"; };
    firewall-wifi = { name = "firewall-wifi"; switch = "wifi-link"; };
    wifi-vm = { name = "wifi-vm"; switch = "wifi-link"; };
  };
}
