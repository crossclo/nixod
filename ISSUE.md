# Known issues

nixod is in test phase. This file lists what is known to be wrong, missing or
untested, so it can be fixed before the first real install.

Sources:
- a **paper walkthrough of `init`** (2026-10-07): a fresh agent, with only
  `template/`, the README, the playbooks (`docs/agent/`) and the code, played a
  user's agent through a whole setup and checked every step against the
  scripts and modules (nothing was run);
- what was found while building nixod (phases 1 to 6).

Severity:
- **Blocker**: `init` can't complete, or something breaks.
- **Problem**: works only with guessing, extra knowledge or luck.
- **Minor**: confusing, inaccurate or incomplete, but not in the way.

Each issue says what happens, why it matters, and, when there is one, how it
could be fixed.

---

## Blockers

### B1. The signed init commit fails when the SSH key has a passphrase

**Where:** `docs/agent/init.md`, steps 3 and 7.

**What happens.** Step 3 has the user create this machine's SSH key, and
suggests a passphrase by default (`nix run .#nixod -- identity host <name>`
without `--no-passphrase`). Step 7 then has the *agent* run:

```sh
git -c gpg.format=ssh -c user.signingkey=~/.ssh/id_ed25519 commit -S -m "nixod: init"
git push origin main
```

To sign with a key that has a passphrase, `ssh-keygen -Y sign` (called by git)
needs either the key loaded in an ssh-agent, or a terminal to ask for the
passphrase. The agent's shell has no terminal, and no ssh-agent holds the key
yet: nixod's ssh-agent (`services.ssh-agent` with `addKeysToAgent = "yes"`, in
`modules/home/profiles/shell.nix`) only exists after the first switch (step 8),
which comes after the commit. So the commit fails. `git push` over SSH can hit
the same wall if the remote is SSH and uses that key.

**Why it matters.** The path the docs recommend (a passphrase) is exactly the
one that breaks, at the step that must succeed for the hub to be installable
(the hub is installed from that commit).

**Fix.** Let the user run the commands that need their passphrase themselves,
in a terminal: the playbook gives them the exact `git commit -S` and
`git push` lines for step 7, and waits. Other options, less simple:
`ssh-add` in a terminal whose agent socket the agent's shell can reach (fragile
across tools), or recommending `--no-passphrase` for the first host (weaker:
this key logs into the hub as root and signs every change).

### B2. The hub's keys are lost if the user logs out or reboots before the hub install

**Where:** `docs/agent/init.md`, steps 5 → 8 → 9; `identity.sh` line 97,
`install-hub.sh` line 71.

**What happens.** `nixod identity hub` (step 5) puts the hub's private keys
(Syncthing identity, SSH host key, deploy key) in
`$XDG_RUNTIME_DIR/nixod/hub-<name>`. That is a tmpfs on purpose, so the keys
never touch a disk, but systemd deletes it when the user's last session ends,
and it is gone after a reboot.

Step 8 is the first switch of the user's machine. Typically it changes the GPU
driver (NVIDIA needs a reboot), the display manager (greetd instead of the old
one) and the desktop (i3). Anyone who wants to *see* their new desktop logs out
or reboots. Step 9 (`install-hub --stage install`) then stops with
`missing …: run 'nixod identity hub' first`.

Running `nixod identity hub` again makes **new** keys, which don't match the
public parts already committed and pushed in `network.nix`. `install-hub` does
notice a Syncthing ID mismatch and refuses, but the SSH host key and deploy key
would differ too. The way out (new identity, update `network.nix`, new signed
commit, push) is written nowhere.

The agent's own session may also die at the logout (see P9).

**Fix.** Install the hub before switching the first machine: step 9 before
step 8. The keys are used while they still exist, the reboot comes last, and
the only cost is the hub running a few minutes with no host connected. Also:
- say plainly, between `identity hub` and `install-hub`: "don't log out or
  reboot until the hub is installed";
- document the recovery when it happens anyway (new `identity hub`, update the
  hub's entry, new signed commit, push), or make `install-hub` detect it and
  print those steps;
- make `install-hub` compare all three staged public keys with `network.nix`,
  not only the Syncthing ID.

### B3. The template has no `.gitignore`: the `result` link gets committed

**Where:** `template/` (no `.gitignore`); `docs/agent/init.md` step 7.

**What happens.** Step 7 runs two `nix build` commands without `--no-link`,
which create a `./result` symlink, then `git add -A`. The framework repo
ignores `result` and `result-*`; the template doesn't. So `result` is
committed.

From then on, every local `nix build` changes `result`, so the tree is dirty
again:
- `nixod update` refuses to run ("uncommitted changes", `update.sh` line 42);
- `nixod install-hub --stage install` refuses (`git diff --quiet HEAD`);
- a flake built from a dirty tree has no `self.rev`, so the system has no
  `configurationRevision`, which update verification relies on.

**Fix.** Add `template/.gitignore` with `result` and `result-*`, use
`nix build --no-link` everywhere in the playbooks, and add a check that the
template has the `.gitignore`.

### B4. `settings.repo.path` is never set: updates fail when the clone isn't at `~/nixod`

**Where:** `docs/agent/init.md` step 1; `template/settings.nix`;
`check.sh`, `update.sh`, `status.sh`; `modules/home/profiles/shell.nix`.

**What happens.** `settings.repo.path` defaults to `~/nixod`. It isn't marked
`NIXOD:FILL` and the playbook never mentions it. `nixod check`, `nixod update`
and `nixod status` look for the clone there and stop with "no clone at …" when
it isn't. The `nrs`/`nrt`/`nfu` shell aliases are built from it too. The user
cloned their repo wherever they liked (say `~/src/nixod-config`), so update
notifications and `nixod update` fail on the first machine from day one, and
on every machine that joins the same way.

**Fix.** In init step 1, set `repo.path` to where the clone actually is
(written `~/…`), and say every machine must clone it to the same place. Join
should check it too: `nixod join` could refuse when the repo isn't at
`settings.repo.path`, and say where to move it.

### B5. `gh` is assumed, never installed or logged in

**Where:** `docs/agent/init.md` ("You need"); `describe-host.md` step 4;
`install-hub.sh` (deploy key).

**What happens.** A fresh NixOS has no `gh`. The init playbook says
"`gh auth status` works" as a prerequisite but never says how to get there.
`gh` is used by `describe-host` step 4 (`gh repo list`, to find the user's
dotfiles) and by `install-hub --stage install` (`gh repo deploy-key add`).
The `nixod` wrapper has `gh` on its PATH, so `install-hub` finds the program,
but it isn't logged in. `join.md` says "`gh auth login` first"; `init.md`
doesn't.

**Fix.** A first step in init, done by the user in a terminal:
`nix run nixpkgs#gh -- auth login` (interactive: browser or token). Then
`gh auth status` before going on. Use `nix run nixpkgs#gh -- …` (or
`nix shell nixpkgs#gh`) in the playbooks until the machine runs nixod's config,
which installs `gh` (git profile).

---

## Problems

### P1. No git identity before the first switch

**Where:** `docs/agent/init.md` step 7; `recover.md` step 2; `join.md`.

**What happens.** On a user that never configured git, `git commit` stops with
"Please tell me who you are". nixod's git profile sets the name and email from
`settings.nix`, but only after the first switch, which comes after the first
commit.

**Fix.** Give the identity on the command line for those commits:
`git -c user.name="<fullName>" -c user.email="<email>" commit -S …`, with
the values just written in `settings.nix`. Same in `recover.md` and for
`nixod join` (which commits too).

### P2. SSH to the VPS isn't set up before it is used

**Where:** `docs/agent/init.md` steps 4, 6, 9; `probe.sh`.

**What happens.** Three things are assumed and never prepared:
- **The VPS's host key.** The first connection asks to accept it. In the
  agent's non-interactive shell, `ssh` (inside `nixod probe`) fails with "Host
  key verification failed", or accepts it blindly if configured that way.
  Nothing says to check the fingerprint.
- **Key login.** Many providers give a root *password* only. The agent can't
  type it, and `nixod probe` and nixos-anywhere need key login without a prompt.
- **Which key.** The docs never say that root login must work with a key, from
  the agent's shell.

**Fix.** A "VPS access" step before `probe`, done by the user in a terminal:
`ssh root@<ip>` once, compare the host key fingerprint with the one in the
provider's panel and accept it, then `ssh-copy-id root@<ip>` if only a password
works. Then the agent checks `ssh -o BatchMode=yes root@<ip> true`.

### P3. `! <command>` may not give the user a real terminal

**Where:** `template/AGENTS.md` ("Secrets stay out of the chat"),
`docs/agent/init.md`, `join.md`.

**What happens.** The docs ask the user to type secrets "in their own terminal
(`! <command>`)". In Claude Code, `!` runs the command through the harness, and
it is not certain it gives a TTY. Commands that prompt need one: `mkpasswd`
(password), `ssh-keygen` (passphrase; `identity.sh` refuses when stdin isn't a
terminal), `gh auth login`, `git commit -S` with a passphrase (B1), the first
`ssh root@<ip>` (P2). `!` is also specific to Claude Code, while `AGENTS.md` is
meant for any agent.

**Fix.** Write "in a separate terminal, in the repo, run: …" everywhere a
secret or a prompt is involved, and mention `!` only as a shortcut where it is
known to work. Unverified: whether Claude Code's `!` gives a TTY. Test it once.

### P4. No mode for an init interrupted halfway

**Where:** `template/AGENTS.md` (mode table); `docs/agent/init.md`.

**What happens.** Mode detection only knows "no machines" (init) and "this
machine is not in `network.nix`" (join). If the session ends partway through
init (logout, crash, context lost), say after step 3, `network.nix` has
machines and this machine is in it, so no row matches. If only the host was
added, the network is even invalid ("there must be exactly one hub"), and
`nix flake check` fails.

**Fix.** A row: "this machine is in `network.nix` but the hub isn't installed
or the init commit isn't pushed → resume `init`". The playbook then needs a
way to tell which step was reached, from things that can be checked:
`settings.nix` filled, `hosts/<name>/` present, entries in `network.nix`,
staged hub keys present, `hardware-configuration.nix` for the hub, init commit
pushed, hub answering. A `nixod init-status` command could print that.

### P5. `hub.md`: the DHCP test is wrong for most VPSes

**Where:** `docs/agent/hub.md`, "Network".

**What happens.** The playbook says "every address has `"dynamic": true` → DHCP".
That never holds:
- every interface has an IPv6 link-local `fe80::` address, which is always
  permanent (not dynamic);
- a static IPv6 next to DHCP IPv4 is common;
- IPv6 from router advertisements (SLAAC) shows as dynamic and would be copied
  as static, breaking when the prefix changes.

So a DHCP VPS would be configured with static addresses. Also not covered:
"/32" setups where the gateway is outside the address's subnet (OVH, Hetzner
and others), where `defaultGateway` alone doesn't work and the route to the
gateway must be declared on-link.

**Fix.** Decide on the **global IPv4** address: dynamic → DHCP, else static.
Treat IPv6 separately: SLAAC (dynamic, from router advertisements) → leave it
to the kernel; a static global address → copy it. Add the /32 case with an
example (an on-link route to the gateway before the default route).
`nixod probe` could print a summary (method per address family, gateway
on-link or not) so the agent doesn't have to derive it from raw `ip -j` output.

### P6. The first switch needs a reboot, and may kill the agent's session

**Where:** `docs/agent/init.md` step 8; `join.md` step 5.

**What happens.** The step says "the user runs `sudo nixos-rebuild switch`" and
that their desktop is in place. With an NVIDIA driver change, a kernel module
change, or a display manager change (GDM → greetd), the switch alone isn't
enough, and the running graphical session can stop during it, taking the agent's
terminal with it.

**Fix.** Say: switch, then reboot. Do it last (after the hub install, see B2).
Possibly use `nixos-rebuild boot` and then a reboot for the first switch, which
doesn't touch the running session.

### P7. VPS memory and CPU type aren't checked

**Where:** `docs/agent/hub.md`; `probe` output.

**What happens.** `nixod probe` reports `memoryKiB` and `arch`, but the
playbook never says to look at them:
- the kexec installer (nixos-anywhere) needs around 1 to 1.5 GB of RAM; on a
  smaller VPS, `install-hub --stage hardware` fails or the VPS hangs;
- an `aarch64` VPS can't be built from an `x86_64` first host without
  cross-building (binfmt emulation or a remote builder).

**Fix.** One line each in `hub.md`: check `memoryKiB` (below about 1.5 GB: warn,
and suggest a bigger plan), check `arch` against the first host's.
`nixod probe` could print these warnings itself.

### P8. The console password's hash is in the repo

**Where:** `template/settings.nix` (`hub.hashedPassword`);
`docs/agent/init.md` step 1; `README.md` Flow 1 step 9 ("nothing secret is ever
stored in the repo").

**What happens.** The hub's console password is the last way back in (recover).
Its SHA-512 crypt hash goes into `settings.nix`: in the private repo, in every
clone, in GitHub Actions checkouts, and in the chat when the user pastes it. A
hash can be attacked offline if the repo ever leaks, and SHA-512 crypt is fast
to guess compared to modern password hashes. This is the same kind of risk as
the recovery key that was dropped (store now, crack later), on a smaller scale.
The README also says nothing secret is in the repo, which isn't quite true.

**Fix.** Use `mkpasswd -m yescrypt` (much slower to attack), ask for a long
generated passphrase, and say in the README that the hash is in the repo. A
stronger option: keep it out of the repo, with `hashedPasswordFile` pointing to
a file put on the hub at install (in the staging dir, like the other hub keys).
Then the hub's console password is set once, at install, and changing it
needs the console or SSH.

### P9. The agent's session can end mid-init

**Where:** `docs/agent/init.md`, all steps.

**What happens.** Several init steps can end the agent's own session: the first
switch (P6), a logout or reboot (B2), a crash. With the conversation gone, the
next agent has to find where things stand (P4).

**Fix.** Same as P4 and B2: put the steps that end sessions last, and make the
state checkable so a new session can resume.

### P10. Porting the old desktop setup conflicts with `desktop-i3`

**Where:** `docs/agent/describe-host.md` steps 2 and 3.

**What happens.** Step 3 says to bring over the services and settings from
`/etc/nixos/configuration.nix`. That file usually has
`services.xserver.displayManager.gdm.enable = true` (or SDDM, LightDM) and a
desktop (GNOME, Plasma). Ported as is, at normal priority, it beats nixod's
`gdm.enable = false` (priority 900): GDM and greetd both start.

Also, the Windows dual-boot advice (a GRUB chainload entry) assumes GRUB. A
machine on systemd-boot, which often already finds Windows when it is on the
same EFI partition, doesn't need it.

**Fix.** In `describe-host`: with `desktop-i3`, don't port the old display
manager or desktop; ask the user whether to keep their old desktop instead.
For dual boot: keep the boot loader the machine already uses; the GRUB entry
is for GRUB with Windows on another EFI partition. More generally, `desktop-i3`
could assert that no other display manager is enabled, with a clear message.

### P11. Hardware config generation: undocumented behavior

**Where:** `docs/agent/init.md` steps 6 and 7.

**What happens.** The walkthrough couldn't tell whether
`install-hub --stage hardware` evaluates the hub's config before the hardware
config exists (which would fail: `mkNetwork` requires the file), and whether
the new file is visible to `nix flake check` in step 7, which runs before
`git add -A`.

This was checked against nixos-anywhere's source (1.13): with
`--generate-hardware-config`, it builds nothing before kexec, writes the file
after kexec, and adds it to git (`git add --intent-to-add`). So it works. But
the docs don't say so, and the order in step 7 only works because of that
detail.

**Fix.** Say it in `init.md` step 6, and add
`git add hosts/<hub>/hardware-configuration.nix` right after it so step 7 no
longer depends on nixos-anywhere's internals.

---

## Minor

### M1. AGENTS.md's table reads as a sequence

"`init` (then `describe-host`, `hub`)" suggests three playbooks in a row, but
`init` calls the other two at its steps 2 and 4. Write "`init` (it uses
`describe-host` and `hub`)".

### M2. `describe-host` step 5 writes into an entry that doesn't exist yet

It says to list the folders in the machine's `network.nix` entry, which is only
created at init step 3 (and join step 2). Move the folder questions to those
steps, or say "you will add them in the entry".

### M3. `~` in `user.signingkey=~/.ssh/id_ed25519`

In `git -c user.signingkey=~/.ssh/id_ed25519`, the shell doesn't expand `~`
(it isn't at the start of a word); it works only because git expands it.
Write `$HOME/.ssh/id_ed25519`.

### M4. No keyboard variant

`settings.keyboard.xkb` is a layout only. Variants (German `nodeadkeys`,
French `oss`, US `intl`) have nowhere to go. Add `keyboard.xkbVariant`
(default `""`), used by `desktop-i3` and the GNOME input source.

### M5. `extraLocaleSettings` isn't brought over

The NixOS installer writes `i18n.extraLocaleSettings` (e.g. `de_DE.UTF-8` for
dates and units) into `/etc/nixos/configuration.nix`. Init step 1 never says to
move it to `settings.extraLocaleSettings`, so the hub (and the user's other
machines) don't get it. Add it to step 1.

### M6. Folder versioning is chosen without asking

Init step 3's example gives `docs` staggered versioning kept for a year. That
is a choice with a disk cost on the hub. `describe-host` asks about folders but
not about versioning. Ask, and explain the options (none, simple, staggered,
trashcan) in one line each.

### M7. An existing Home Manager config's `home.stateVersion`

The template sets `home.stateVersion = "25.11"`. If the user already has a Home
Manager config, its `home.stateVersion` must be kept (it changes how some files
are managed). `describe-host` step 4 should say so.

### M8. Copying the probe's kernel modules can break the hub's initrd

`hub.md` says to add `kernelModules` from the probe to
`boot.initrd.availableKernelModules`. They are already in the generated
hardware config (step 6). A module that only exists on the provider's distro
(an Ubuntu name, a renamed driver) breaks the initrd build. Say to rely on the
hardware config, and add a module only if it is missing there.

### M9. "The version the repo pins" before `flake.lock` exists

The first `nix run .#nixod` creates `flake.lock`, pinning the newest nixod at
that moment. "It uses the version the repo pins" is only true from then on.
Say that the first run creates the lock, and that it must be committed.

### M10. Data disks: where `nofail` goes

A data disk is already in the generated hardware config.
`describe-host` says to mount it by UUID with `nofail`, but not that it goes in
`hosts/<name>/default.nix` (`fileSystems."<mount>".options = [ "nofail" ];`),
not by editing the generated file.

---

## Not tested yet

Everything below passed its tests in VMs only partly, or not at all. It runs
for the first time on real machines.

### T1. `nixos-rebuild switch` after an update

In the VM tests for updates and joins, the final `nixos-rebuild switch` is
replaced by a stand-in that records the commit: a VM has no internet to build
a system with. Fetching, verifying, fast-forwarding and calling the switch are
real; the switch itself, inside `nixod-update.service` on the hub (with
`restartIfChanged = false`), has never run.

### T2. kexec (`install-hub --stage hardware`)

The hub install was tested on a VM with an empty disk, without kexec (it
downloads an installer image from the internet). The hardware stage, and the
install stage's kexec, come straight from nixos-anywhere, which tests them
itself, but not with nixod's flake.

### T3. GitHub's side

Never run: `gh pr create` (`nixod join`), fetching a request by PR number
(`refs/pull/<n>/head`), GitHub marking the PR merged after `nixod approve`,
`gh repo deploy-key add` (`install-hub`), and the template's CI workflow on a
real instance repo.

### T4. `nixod probe` on a real VPS

Only tested in `--dry-run`. Its JSON is built by hand in shell
(`probe-remote.sh`) and has never been parsed from a real distribution's
output.

### T5. The desktop

The host modules (i3, greetd, Home Manager profiles) are evaluated in the
checks (`eval-host`) but never built and never booted. The VM tests use hosts
without a desktop.

### T6. Syncthing between real hosts

Hosts use Syncthing's defaults for discovery: global discovery, relays and LAN
discovery are on. The VM test showed that two hosts on the same LAN connect
directly in the second after start, before nixod's settings are applied. That
is allowed (the README says hosts on the same network may talk directly), but:
global discovery announces each device to Syncthing's public servers. Whether
to keep it (useful for laptops away from home) or turn it off (only the hub,
at its fixed address) is not decided.

---

## Other open points

### O1. nixos-25.11 is probably out of support

The framework, the template and the tests use `nixos-25.11` and Home Manager
`release-25.11`, the release the original dotfiles used. A NixOS release is
supported for about seven months, so 25.11 is likely past its end of support
by now. Move to the current stable release (26.05), and check the ported
options still exist.

### O2. The syncthing user ID is hard-coded at install

`install-hub` chowns the staged Syncthing identity to `237:237`, NixOS's fixed
ID for the `syncthing` user (`ids.uids.syncthing`). If NixOS ever changes it,
the hub's Syncthing can't read its own keys. It could read the ID from the
hub's built config instead.

### O3. The framework's CI only runs on demand

The framework's checks (VM tests included) no longer run on push; they run when
started by hand (`gh workflow run check -R crossclo/nixod`). Changes can be
pushed without the checks having run anywhere.

### O4. Only the tip of an update is checked

By design, a signed commit vouches for everything under it (a join request's
unsigned commits are accepted once a trusted machine merges them). This makes
`nixod review` the real security boundary: whatever a trusted machine merges,
every machine applies. The review flags files outside `network.nix` and the
new host's directory, but not what happens inside `network.nix`: a request can
give the new machine folders the user never meant to share with it, or change
other machines' entries. Both show in the `network.nix` diff, so they depend on
the reviewer (the user and their agent) reading it. `nixod review` could flag
them too: any change to an entry other than the new machine's, and list the
folders the new machine gets. Worth stating in the README as well.
