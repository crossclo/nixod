# nixod: technical plan

This plan is built on the README (the concepts and the three flows). It covers the
repo layout, the data model, the helper tool, the update and trust mechanism, the
agent instructions, and the order in which to build it all.

---

## 0. Architecture decision: framework + instance

nixod is split into **two repos**:

| Repo | Visibility | Contents |
|---|---|---|
| `nixod` (framework) | public | NixOS/Home Manager modules, the `lib` that builds a machine's config, the `nixod` CLI, agent playbooks, the flake template |
| `<user>/nixod-config` (instance) | **private** | `network.nix`, `settings.nix`, `hosts/`, personal home overrides, `AGENTS.md`, `flake.lock` |

The instance is created with `nix flake init -t github:crossclo/nixod` in a
new repo (`git init -b main`), then pushed as a private GitHub repo (`gh repo
create --private --source . --push`). GitHub's "Use this template" button on
nixod would copy the framework, not `template/`. The instance uses the
framework as a flake input.

**Why:** fixes to the security-critical parts (signature checks, update units,
config generation) reach every user through `nix flake update nixod`. With a
template you copy once, each user would have to merge fixes by hand forever.
Personal taste (desktop, theme, packages) stays in the instance.

---

## 1. Repo layouts

### Framework (`nixod`)

```
flake.nix                 # exposes nixosModules, homeModules, lib, packages.nixod, templates.default
lib/
  default.nix             # mkNetwork: network.nix + settings.nix + hosts/ → nixosConfigurations
  derive.nix              # pure functions: Syncthing devices/folders, SSH keys, allowed_signers
modules/
  nixos/
    core.nix              # user, nix settings, locale/time/keymap from settings
    nixod/
      syncthing.nix       # Syncthing config generated from network.nix
      ssh.nix             # knownHosts (hub), authorizedKeys (on hub), allowed_signers file
      update.nix          # hub: automatic updates; hosts: check + notify, `nixod update`
      hub.nix             # hub role: sshd hardened, headless, Syncthing as system user
    profiles/             # opt-in, enabled per host via nixod.profiles.<name>.enable
      desktop-i3.nix  audio.nix  networking.nix  zram.nix  security-hardening.nix
                          # hardware- and use-specific config (GPU driver, laptop
                          # power, Steam, Docker...) is NOT a profile: the agent
                          # writes it as plain NixOS options in hosts/<name>/
  home/
    profiles/             # default user setup, from bennie's dotfiles with personal data removed
      shell.nix  terminal.nix  neovim.nix  i3.nix  rofi.nix  notifications.nix
      gtk.nix  git.nix  dev.nix  apps.nix
                          # personal tool sets (anything user-specific) are NOT
                          # shipped here: they live in the user's private instance, under home/
    theme/colors.nix      # default palette, overridable
pkgs/nixod/               # the CLI (shell, writeShellApplication)
docs/agent/               # playbooks the agent follows (init, describe-host, hub, join, review,
                          # change, remove, recover), shipped in the CLI: `nixod doc <name>`
template/                 # what `nix flake init -t` copies (= instance skeleton)
tests/                    # nixosTest VM tests (sync, update, signatures)
```

### Instance (`nixod-config`, made from `template/`)

```
flake.nix                 # inputs: nixpkgs, home-manager, disko, nixod → nixod.lib.mkNetwork { ... }
settings.nix              # user-wide settings (FILL markers)
network.nix               # the list of machines (empty at first)
hosts/
  <name>/
    default.nix           # profiles + host-specific config
    hardware-configuration.nix   # MANDATORY, generated on the machine itself (nixos-generate-config)
    disko.nix             # hub only
home/
  default.nix             # personal overrides / imported dotfiles
  <name>.nix              # personal tool sets that stay private
AGENTS.md                 # agent entry point (CLAUDE.md → symlink)
.github/workflows/check.yml
```

---

## 2. Data model

### `settings.nix`: who you are

```nix
{
  user = {
    name = null;            # NIXOD:FILL  login name
    fullName = null;        # NIXOD:FILL
    email = null;           # NIXOD:FILL  git identity
  };
  timeZone = null;          # NIXOD:FILL  e.g. "Europe/Paris"
  locale = "en_US.UTF-8";
  keyboard = { console = null; xkb = null; };   # NIXOD:FILL
  repo = {
    url = null;             # NIXOD:FILL  git@github.com:<user>/nixod-config.git
    branch = "main";
    path = "~/nixod";       # where the clone lives on hosts
  };
}
```

Every `null` marked `NIXOD:FILL` is checked by an **assertion**. `nix flake check`
fails with a clear message ("settings.user.name is not set") until the agent fills
it. The agent finds what's left to fill with `grep -rn NIXOD:FILL`.

### `network.nix`: the list of machines

```nix
{
  machines = {
    vps = {
      role = "hub";
      address = "203.0.113.10";
      syncthingId = "AAAAAAA-...";
      sshHostKey = "ssh-ed25519 AAAA...";       # for knownHosts everywhere
      deployKey = "ssh-ed25519 AAAA...";        # read-only GitHub deploy key (public part)
    };
    tower = {
      role = "host";
      syncthingId = "BBBBBBB-...";
      userKey = "ssh-ed25519 AAAA...";          # logs into the hub + signs commits
      folders = {
        projects = "/home/alice/sync/projects";
        docs     = "/home/alice/sync/docs";
        media    = "/home/alice/Storage/media";
      };
    };
  };

  folders = {
    projects = { versioning = { type = "staggered"; params.maxAge = "2592000"; }; };
    docs     = { versioning = { type = "staggered"; params.maxAge = "31536000"; }; };
    media    = { hub.ignoreDelete = true; versioning = { type = "trashcan"; params.cleanoutDays = "30"; }; };
  };
}
```

### What is built from it (`lib/derive.nix`)

All of these are pure functions of `network.nix`, unit-tested with `nix eval`:

| Output | On | Rule |
|---|---|---|
| Syncthing `devices` | host | the hub (with `addresses = [ "tcp://<ip>:22000" "dynamic" ]`) + every other host |
| Syncthing `devices` | hub | every host |
| Syncthing `folders` | host | every folder in its `folders`, shared with the hub + every other host that has it |
| Syncthing `folders` | hub | the union of all hosts' folders, at `/var/lib/syncthing/<id>`, plus folder-level `hub.*` options |
| `systemd.tmpfiles` | host | create each folder path (Syncthing needs them to exist) |
| `authorizedKeys` | hub (root + user) | every host's `userKey` |
| `programs.ssh.knownHosts` | all | the hub's `sshHostKey` |
| `/etc/nixod/allowed_signers` | all | one line per host `userKey` |

`overrideDevices` / `overrideFolders` stay `true`. The introducer is removed.
Global discovery and relays are off (hosts reach the hub at its fixed address,
and the hub keeps everything); local discovery stays on, so hosts on the same
LAN may talk directly.

### Profiles instead of hostname checks

Hosts enable features as options: `nixod.profiles.desktop-i3.enable = true;`.
Home modules read them through `osConfig.nixod.profiles.*`, or detect hardware
at runtime (the bar shows a battery only if `/sys/class/power_supply/BAT*`
exists). This replaces things like `isLaptop = hostName == "Layla"`.

### Everything the framework sets is a default

Profiles set their values through `lib/defaults.nix` (priority 900: above the
`mkDefault` NixOS and Home Manager use, below a plain definition). An instance
overrides one value (one alias, one color, one sysctl) by setting it, and keeps
the rest. Additive lists (packages, plugins, startup commands) stay at normal
priority and merge with the instance's.

---

## 3. The `nixod` CLI

The CLI is the **default way to do things, not the only way**. It covers the
normal case and makes it deterministic and testable. The agent stays free to step
outside it when a case doesn't fit, for example:
- a VPS provider with an unusual boot or network setup;
- a disk layout disko's default can't express;
- a GitHub org with different permissions.

To make that easy:
- **Every command is a short shell script made of named steps.** The agent can
  read it, run a step by hand, or pass extra arguments through (for example,
  `install-hub -- <extra nixos-anywhere flags>`).
- **`--dry-run` on every command** prints the steps and the exact commands
  without running anything.
- **When the agent leaves the CLI, it tells the user** what it does differently
  and why.

What the agent may change is **how** a step is done. The **invariants** in §6
can't be changed: no private key in git, confirmation before wiping a disk, never
skipping or weakening update verification, and changes are made in the repo, not
by hand on a machine.

| Command | Where | Does |
|---|---|---|
| `nixod identity host <name>` | new host | generates the Syncthing identity into `~/.config/syncthing` and this machine's own SSH key `~/.ssh/nixod_ed25519` if missing (no passphrase unless `--passphrase`: the agent signs with it); prints the IDs |
| `nixod identity hub <name>` | first host | generates the hub's Syncthing identity, SSH host key and deploy key in a staging dir (`$XDG_RUNTIME_DIR`, tmpfs); prints the public parts. `--console-password` (the user, in a terminal) stages the yescrypt hash of the hub's console password |
| `nixod probe root@<ip>` | first host | reads the VPS's stock OS: interfaces, addresses, routes, DNS, disks, memory, arch, BIOS/UEFI. Prints JSON for the agent, with a `summary` worked out locally (`probe-summary.jq`): IPv4/IPv6 method and addresses, gateway outside the subnet, the disk, warnings (memory, arch, several disks). `--from-json` summarizes a saved probe |
| `nixod init-status [<name>]` | first host | where an interrupted init stands: checks each init step against the repo, the staging dir, GitHub and the VPS, prints the step to continue at (`--offline`: no network checks) |
| `nixod install-hub <name> root@<ip>` | first host | checks the staged Syncthing ID, host key and deploy key match `network.nix` and the console password is staged; adds the deploy key on GitHub (`gh repo deploy-key add`, read-only by default), runs `nixos-anywhere --extra-files <staging> --chown …`, puts the hub's host key in `known_hosts`, then wipes the staging dir |
| `nixod join` | new host | checks the clone is at `settings.repo.path`; branch `join/<name>`, commit, push, `gh pr create` (`--no-pr`: push only) |
| `nixod review <pr\|branch>` | trusted host | fetches the request, shows the machines added/removed and the folders each new one gets, the `network.nix` diff and the files touched; warns about changes to other machines' entries or folder options, and (with the full diff) about any file outside `network.nix` and the new host's `hosts/<name>/`; builds the new host and the hub; records the reviewed commit |
| `nixod approve <pr\|branch>` | trusted host | refuses unless the request is exactly the reviewed commit, and unless `main` verifies (a signed merge vouches for it too); `git merge --no-ff -S` locally, push. GitHub marks the PR merged |
| `nixod check` | hosts (timer) | fetch + verify; notifies if a verified update is waiting |
| `nixod update` | hosts | verify, fast-forward, `nixos-rebuild switch`. `--first <name>`, right after a join: trusts the hosts of its own join request's `network.nix`, then `nixos-rebuild boot` |
| `nixod remove <name>` | trusted host | after the entry is deleted from `network.nix`: deletes `hosts/<name>/`, builds the hub, signed commit, push |
| `nixod status` | any | running commit vs `main`, Syncthing peers, last hub update |
| `nixod doc [<name>]` | any | prints a playbook of this nixod version (no name: lists them) |
| `nixod trust-once --from <name>` | hub, **provider console only** | reads `machines.<name>.userKey` from `network.nix` on GitHub, shows its fingerprint, asks to confirm; then trusts that key for the next commit signed by it (or a day), once. Also takes the key itself |

Before a machine runs nixod (init, join, recover), the CLI comes from the
instance itself: `nix run .#nixod -- <command>` (the instance flake exposes
`packages.nixod` from the framework version it pins).

---

## 4. Updates and trust

### Signature verification (shared by the hub and hosts)

```
cur = commit the running system runs: the last one the hub applied
      (/var/lib/nixod/revision), else the one it was built from
      (system.configurationRevision = self.rev). On a host built from a dirty
      tree (no revision), the user's clone HEAD stands in.
new = origin/<branch> after fetch

1. new == cur                       → nothing to do
2. git merge-base --is-ancestor cur new   else REJECT (blocks history rewrites / rollback to an old signed commit)
3. trusted = /etc/nixod/allowed_signers (+ the trust-once key, on the hub)
   for c in cur..new (ancestry path, oldest first), new excluded:
     if c changes network.nix (vs the last trusted point) and
        git verify-commit c with trusted:
       trusted = the hosts' userKeys in network.nix at c
4. git verify-commit new  with trusted   else REJECT
```

- The trust starts from the **running** system, never from the incoming
  commit. A commit can't vouch for itself by adding its own key: its
  network.nix only counts for the commits after it, once it is itself signed
  by a key trusted before it.
- **Never sign on top of what doesn't verify.** A signed commit vouches for
  its whole tree, so `approve` and `remove` refuse unless their base passes
  the same check (`check_base`), and the playbooks check before pulling.
  Unverified commits on GitHub are shown to the user, who accepts them
  explicitly or undoes them in a signed commit.
- A join request's `network.nix` is read in Nix's restricted mode (alone in
  a directory, no fetches): `network.nix` is plain data.
- Trust follows the history, so a machine that is behind (a laptop off for
  weeks, or the hub when two commits land within one timer period) accepts a
  commit signed by a host added since, and refuses one signed by a host
  removed since. A network.nix that doesn't evaluate on its own leaves the
  trust as it was.
- Only the **tip** has to be signed. A signed merge from a trusted machine vouches
  for everything under it, including the join PR's unsigned commits.
- Commits are signed with SSH keys. Home Manager sets
  `programs.git.signing = { format = "ssh"; key = "~/.ssh/nixod_ed25519"; signByDefault = true; }`.
  Each machine has its own key, made by `nixod identity host` and never
  shared: `network.nix` refuses a `userKey` used twice, so removing a machine
  always revokes its key. It has no passphrase at first, so the agent can
  sign; the user may add one (`ssh-keygen -p`) and load it into the
  ssh-agent once per session. With a passphrase, `nixod.home.ssh.confirm`
  adds a confirmation dialog for each use of the key (`AddKeysToAgent
  confirm`, x11-ssh-askpass, the agent started in the graphical session): a
  human check on every signature and hub login.

### Hub: automatic (`update.nix`)

- `nixod-update.timer`, every 5 minutes.
- Its own clone at `/var/lib/nixod/repo`, fetched with the **read-only deploy
  key** (set up at install via `--extra-files`).
- Verify → fast-forward → `nixos-rebuild switch --flake /var/lib/nixod/repo#<hub>`.
- If the build or the check fails, the current generation keeps running. The
  error goes to the journal and shows in `nixod status`.

### Hosts: notify, you apply (`update.nix`)

- User-level `nixod-check.timer`: 5 minutes after login, then hourly.
- Works in the user's own clone (`settings.repo.path`) using the user's GitHub
  access. **Fetch only**: it never touches the working tree.
- When a verified update is waiting: `notify-send "nixod" "3 changes ready: run nixod update"`
  with the commit subjects. Needs a notification daemon, which the default desktop
  profile includes.
- `nixod update` stops if the working tree is dirty or has diverged, and says why.

### Recovery: every host lost, only the hub left

If no host's key survives, nobody can sign and the hub rejects everything. Data is
safe because the hub keeps syncing, but nobody can get back in. **Reinstalling
the hub is never the answer:** disko wipes the disk, and at that moment the hub
holds the only copy of the data.

**The provider console.**
- The hub's console password is **required at init**. This is the provider
  VNC/serial console, never SSH, where password login stays disabled. It is
  not in the repo: the user types it (`nixod identity hub --console-password`),
  its yescrypt hash is staged with the hub's keys and installed as
  `/var/lib/nixod/console-password` (`hashedPasswordFile`). Users are mutable,
  so it is read when the user is created; it is changed with `passwd` on the
  hub.
- The new machine is described and gets its identity, as in a join, and its
  entry is committed (signed with its own key).
- The new host pushes its commit first; the hub rejects it for now.
- On the console: `nixod trust-once --from <name>` reads the new host's key from
  that commit, shows its fingerprint to compare with the new machine's, and
  writes `/var/lib/nixod/trust-once`. The first new commit signed by that key
  is checked with it, once, accepted or not; then the file is deleted. Commits
  not signed by it leave it waiting; unused, it expires after a day.
- The hub applies the commit, and the host is in `network.nix` for good.
- The command refuses to run outside a local console: no SSH variables, and
  the login session (which `sudo -i` keeps) must be local (logind's
  `Remote=no`), so it can only be used from the console.
- Before the recovery commit, the agent compares `main` with the commit the
  hub runs (`nixod status` on the console): the recovery commit, signed by the
  trust-once key, would vouch for anything unsigned in between.

**Not implemented, on purpose: a recovery key.** The idea was a key not tied to a
machine, its public part in `allowed_signers`, its private part in the repo
encrypted with a generated passphrase (10 diceware words, about 128 bits), and
`nixod recover` to sign with it from a fresh machine. It is left out for safety:
anyone who ever gets a copy of the repo (a leak, a fork, a backup) could keep the
encrypted key and attack it later ("store now, decrypt later"), with better
hardware or a weakness found in the KDF. The console path stores nothing. If it
comes back, the key should live outside the repo (paper, hardware token).

**Unrecoverable only if** every host and the provider account (or the console
password) are all lost. If GitHub access is lost too, `/var/lib/nixod/repo` on the hub is a full
clone.

---

## 5. Flows, technically

### Init (first host + hub)

The steps that can end the agent's session (logout, reboot) come last, and an
interrupted init can be resumed from what the repo and the machine show
(`init` playbook, "Resuming", and `nixod init-status`).

0. **User:** `gh auth login` (HTTPS).
1. The agent detects **init mode**: `network.nix` has no machines.
2. Fills `settings.nix` (asks the user), `repo.path` included; sets the git
   identity for the repo.
3. Describes the host (see §6) → `hosts/<name>/`.
4. `nixod identity host <name>`, then adds the host to `network.nix`.
5. **User:** accepts the VPS's host key (checked against the provider's
   panel) and authorizes this machine's key on it (`ssh-copy-id`).
6. `nixod probe root@<ip>` → writes `hosts/<hub>/` (static network or DHCP,
   `disko.nix` with the right disk, BIOS/UEFI boot loader).
7. `nixod identity hub <hub>`, then **the user** stages the console password
   (`--console-password`); the agent adds the hub to `network.nix`. From here
   to the hub install, no logout or reboot: the staged keys are in RAM.
8. **Hub hardware configuration**, `nixod install-hub --stage hardware`
   (confirm first: the provider OS is replaced in RAM until the next reboot; the
   disk is not touched yet). nixos-anywhere boots its installer through kexec,
   then runs `nixos-generate-config --no-filesystems` there (disko declares the
   file systems) → `hosts/<hub>/hardware-configuration.nix`, added to git.
9. `nix flake check`, build both configs, signed commit, push. The hub is
   installed from this clean commit, so it knows which revision it runs.
10. **Asks the user to confirm before wiping the VPS disk**, then
    `nixod install-hub --stage install` (disko + install + reboot).
11. **User:** `sudo nixos-rebuild boot --flake .#<name>`, then reboot (the
    display manager and the desktop change: the running session wouldn't
    survive a switch).
12. After the reboot, a new agent session: `nixod status` → the hub is up and
    Syncthing is connected; offers a passphrase for the key; makes sure the
    user has kept the hub's console password and access to the provider
    account: with every host lost, they are the way back in.

> Checked in phase 3 (nixos-anywhere 1.13): the two runs work. `--phases kexec
> --generate-hardware-config nixos-generate-config <path>` boots the installer and
> runs `nixos-generate-config --no-filesystems` without touching the disk. The
> install run lists `kexec,disko,install,reboot`; nixos-anywhere skips kexec when
> the target already runs the installer, and kexecs again if the VPS rebooted in
> between. `install-hub` builds first and passes `--store-paths`, and refuses to
> install when the staged Syncthing ID is not the one in `network.nix`.

### Join

1. The agent detects **join mode**: the hostname is not in `network.nix`.
2. Describes the host (§6: hardware configuration first, then detection,
   config, dotfiles), `nixod identity host`, adds the entry.
3. `nixod join` → PR. CI checks it.
4. Trusted host: `nixod review <pr>` → user reads → `nixod approve <pr>`.
5. The hub applies it on its own (≤ 5 min).
6. New host: `nixod update --first <name>` (verifies the approval against the hosts of its own request's `network.nix`, then `nixos-rebuild boot`), then reboot. Other hosts get notified later.

---

## 6. `AGENTS.md` and the playbooks

`AGENTS.md` (instance) is short. It contains:
- **what nixod is** (a link to the README) and **mode detection** (init / join /
  review / change / remove / recover), each pointing to a playbook in the
  framework's `docs/agent/`, read with `nixod doc <name>` (the version the
  instance pins);
- **invariants (never broken, whatever the case):**
  - never commit a private key;
  - get explicit confirmation before anything that wipes a disk, and **never
    reinstall a hub that holds data**;
  - never skip, weaken or work around update verification;
  - change machines through the repo, never by hand on the machine (the
    provider-console recovery is the only exception);
  - build before asking the user to switch.
  - secrets stay out of the chat: passwords and passphrases are typed by the
    user in their own terminal, never by the agent.
- **default ways of working (adaptable):**
  - use the `nixod` CLI for identities, installs, signing and merging;
  - if a case doesn't fit, read the script, run or adapt its steps by hand, and
    tell the user what is different and why;
  - if the fix is general, suggest it upstream to the framework.

Describing a host (shared by init, join and recovery), in this order:

**Step 1: NixOS hardware configuration (mandatory, always first).**
- `nixos-generate-config --show-hardware-config > hosts/<name>/hardware-configuration.nix`,
  run **on the machine itself**. Never copied from another machine or written
  by hand.
- Compare with the existing `/etc/nixos/hardware-configuration.nix`. Anything
  added by hand there (extra mounts, kernel modules, options) is kept, either in
  the new file or in `hosts/<name>/default.nix`, and shown to the user.
- `mkHost` requires this file: a host without it fails `nix flake check` with a
  clear message.
- Hub: generated during the install (see §5).

**Step 2: Hardware detection → profiles and host options.**
- `lspci`: NVIDIA GPU → NVIDIA driver config, with driver choice by generation
  (open driver vs proprietary; Pascal and older → proprietary, like Poppy).
  AMD/Intel → no extra driver.
- `/sys/class/power_supply/BAT*` → laptop config (power profiles, upower,
  touchpad).
- CPU vendor (`/proc/cpuinfo`) → microcode, thermald only on Intel.
- `lsblk -f` + `efibootmgr`: another OS's EFI partition → GRUB with a chainload
  entry (Poppy and Layla are the models).
- Extra data disks → mounts by UUID with `nofail`.
- No swap partition → zram (plus a swapfile when there's little RAM).
- The agent shows what it detected and the profiles it plans to enable, and the
  user confirms.
- All of this is written as plain NixOS options in `hosts/<name>/default.nix`.
  The framework ships no hardware-specific profiles.

**Step 3: Existing config.** `/etc/nixos/configuration.nix` → bring over the
services, packages and settings that aren't hardware.
**Step 4: Dotfiles.**
  - look locally (`~/.config`, `~/.zshrc`, `~/.gitconfig`, an existing Home Manager
    config) and on GitHub (`gh repo list` → repos that look like dotfiles);
  - port them to Home Manager options where they exist, otherwise
    `xdg.configFile`/`home.file`;
  - otherwise use the framework's default profiles.
**Step 5: Questions for the user.** Which folders this host syncs and where.

---

## 7. CI (`.github/workflows/check.yml`)

- Install Nix, then `nix flake check`. This covers evaluating every machine,
  the `NIXOD:FILL` assertions, and validating `network.nix` (unique names, valid
  IDs, folders that exist, exactly one hub).
- Only evaluation, no full desktop builds (too heavy for CI). The real build
  happens in `nixod review` on the trusted machine.

---

## 8. Testing

- **`lib/derive.nix`:** `nix eval` unit tests (network → expected Syncthing/SSH
  config).
- **VM tests (`nixosTest`):**
  - hub + 2 hosts: a file written on host A shows up on host B with A and B never
    connected directly;
  - updates: a local bare repo as "GitHub". A signed commit is applied; an
    unsigned commit, a commit signed by an unknown key, and a rollback are all
    rejected; a host gets a notification;
  - removal: a removed host's key no longer verifies;
  - recovery: with every host key gone, `trust-once` accepts exactly one update
    signed by the new host's key, is then cleared, and refuses to run over SSH.
- **nixos-anywhere:** a local QEMU VM running Debian as the fake VPS, then one real
  test on a throwaway VPS.
- **Dogfooding:** move bennie's real network (Poppy, Layla, VPS) onto nixod as the
  final acceptance test.

---

## 9. Build order

| Phase | Deliverable | Done when |
|---|---|---|
| 1. Framework skeleton | modules/profiles ported from the dotfiles (all modules except the personal tool list in `home/security.nix`, which is not read or ported), personal data removed; `settings.nix` + assertions; template | a dummy host evaluates; CI green |
| 2. The network | `network.nix` schema, `derive.nix`, `syncthing.nix`, `ssh.nix` | eval tests + 3-node sync VM test pass |
| 3. CLI: identities + hub | `identity`, `probe`, `install-hub` | the hub installs on a local VM with a known ID |
| 4. Updates and trust | verification script, `update-hub`, `update-host`, notification, `trust-once` | update + recovery VM tests pass (accept + all rejections) |
| 5. Join | `join`, `review`, `approve`, CI workflow | a full join flow works between two VMs |
| 6. Agent | `AGENTS.md`, playbooks | a fresh agent completes init on VMs from the README alone |
| 7. Dogfood | bennie's network migrated | Poppy, Layla and the VPS run on nixod; old dotfiles archived |

---

## Open points

- **Hub admin access:** keep SSH to the hub for every host (debugging), or only
  through git? Current plan: every host `userKey` can SSH in.
- **Default desktop:** ship bennie's i3 setup (personal data removed) as the
  default, or look for a well-known community config on GitHub. Current plan: i3
  default, and the user's own dotfiles always come first.
