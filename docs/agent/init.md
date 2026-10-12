# init: set up the network (first host + hub)

Mode: `network.nix` has no machines. You are on the user's first machine,
which already runs NixOS, in a clone of their **private** instance repo.
If `network.nix` already lists this machine but it doesn't run nixod yet
(no `/etc/nixod/config`), an earlier init was interrupted: see **Resuming**
at the end.

You need from the user: a VPS reachable as `root@<ip>` over SSH (any provider,
stock OS), a GitHub account, and answers to a few questions. Expect the whole
flow to take an hour, most of it builds.

Until this machine runs nixod, `nixod` is not installed: in this playbook,
`nixod ...` means `nix run .#nixod -- ...`, run in the repo (it uses the
framework version the repo pins). If flakes aren't enabled yet, every `nix`
command needs `--extra-experimental-features "nix-command flakes"`. `gh` isn't
installed either: `gh ...` means `nix run nixpkgs#gh -- ...`.

**The user's terminal.** Some steps need the user to type something (a login,
a password, accepting a host key). Ask them to run those **in a separate
terminal, in the repo**, and give them the exact command. `! <command>` in
Claude Code gives no terminal (`! tty` says "not a tty"): don't use it for
anything that prompts. Passwords never go through the chat.

**Order matters.** The steps that can end your session (logging out,
rebooting) come last. From step 6 to step 9 the hub's private keys live in
RAM only: tell the user **not to log out or reboot** until the hub is
installed.

## 0. GitHub login (the user)

In a separate terminal:

```sh
nix --extra-experimental-features "nix-command flakes" run nixpkgs#gh -- auth login
```

Tell them to pick **GitHub.com**, **HTTPS**, and yes to "Authenticate Git
with your GitHub credentials". Not SSH: nixod makes this machine's own key
later, and must not get one that gh generated. Then check yourself:
`gh auth status`.

## 1. Settings

Fill every `NIXOD:FILL` in `settings.nix` (`grep -n NIXOD:FILL settings.nix`):

- `user.name`, `user.fullName`, `user.email`: ask. Default `user.name` to the
  current login (`id -un`).
- `timeZone`, `keyboard.console`, `keyboard.xkb`: read them from the current
  system (`timedatectl`, `/etc/nixos/configuration.nix`), confirm with the user.
  A layout variant (`services.xserver.xkb.variant`, e.g. `oss`) goes in
  `keyboard.xkbVariant`.
- `extraLocaleSettings`: copy `i18n.extraLocaleSettings` from
  `/etc/nixos/configuration.nix` if it is there (`LC_TIME`, `LC_MONETARY`...).
- `repo.url`: the SSH form, `git@github.com:<user>/<repo>.git` (the hub fetches
  with a deploy key, over SSH). This clone's own remote can stay HTTPS.
- `repo.path`: where this clone is, written with `~` (`~/src/nixod-config`),
  not `~/nixod` by default. Update checks and `nixod update` look for it there.
  Tell the user every machine keeps its clone at that same place.

Git doesn't know the user yet (nixod's git config comes with the switch, at
the end). Set it for this repo only, with the values just written:

```sh
git config user.name "<fullName>"
git config user.email "<email>"
```

## 2. Describe this machine

Follow `nixod doc describe-host`. Result: `hosts/<name>/`, with
`hardware-configuration.nix` generated on this machine, and the user's setup
in `home/` and `system/` (their dotfiles, plus the starter files they chose).

## 3. This machine's identity

```sh
nixod identity host <name>
```

The first `nix run .#nixod` writes `flake.lock`: it pins the nixod version
from now on, and is committed with the rest.

It makes this machine's own key, `~/.ssh/nixod_ed25519`, **without a
passphrase**: you sign the init commit and log into the VPS with it, and you
have no terminal to type a passphrase in. The user can add one at the end.
If the key already exists with a passphrase, it says so: ask the user to run
`ssh-add ~/.ssh/nixod_ed25519` in their terminal, and check `ssh-add -l` in
yours shows it (if your shell doesn't reach their ssh-agent, the user runs
the signed commit and the SSH steps themselves).

It prints `syncthingId` and `userKey`. Ask which folders this machine syncs,
where, and how each keeps old versions (each one has a disk cost on the hub):
- none: deleted and overwritten files are gone;
- `trashcan`: deleted files kept N days (`params.cleanoutDays = "30"`);
- `simple`: the last N versions of each file (`params.keep = "5"`);
- `staggered`: versions thinned out over time, up to a maximum age
  (`params.maxAge` in seconds: `"31536000"` is a year).

Add the machine to `network.nix`:

```nix
machines.<name> = {
  role = "host";
  syncthingId = "...";
  userKey = "ssh-ed25519 ...";
  folders = { photos = "/home/<user>/sync/photos"; };   # folder name → path here
};
folders.photos = { versioning = { type = "trashcan"; params.cleanoutDays = "30"; }; };
```

## 4. VPS access (the user)

The nixod commands reach the VPS as root, with this machine's key and no
prompt. The user sets that up once, in a separate terminal:

```sh
ssh root@<ip>                                     # 1
ssh-copy-id -i ~/.ssh/nixod_ed25519.pub root@<ip>  # 2
```

1. The first connection shows the VPS's host key fingerprint. They compare it
   with the one in the provider's panel (or console: `ssh-keygen -lf
   /etc/ssh/ssh_host_ed25519_key.pub`) and answer `yes` only if it matches.
2. Authorizes this machine's key (asks the root password once, if that's how
   the provider gave access).

Then check from your shell:
`ssh -i ~/.ssh/nixod_ed25519 -o BatchMode=yes root@<ip> true`.

That host key, now in `~/.ssh/known_hosts`, is what `nixod install-hub`
holds the VPS to: it refuses to install if the key isn't there, or if the
VPS presents another one.

## 5. Look at the VPS

`nixod probe root@<ip>` prints JSON (read-only). Write `hosts/<hub>/default.nix`
and `hosts/<hub>/disko.nix` from it: `nixod doc hub`. Ask the user for the hub's
name (default `hub`).

## 6. The hub's identity

```sh
nixod identity hub <hub>
```

Its keys go to a tmpfs staging dir (never the repo). Then the user, in a
separate terminal, sets the hub's **console password** (the provider's web
console only; SSH never accepts passwords):

```sh
nix --extra-experimental-features "nix-command flakes" run .#nixod -- identity hub <hub> --console-password
```

It asks twice and stages a yescrypt hash, which goes onto the hub at install:
the password and its hash never enter the repo or the chat. Tell the user to
keep the password somewhere safe (a password manager): with every machine
lost, it is the way back in (`nixod doc recover`).

Remind them: **no logout, no reboot until step 9 is done** (the staged keys
are in RAM).

Add the hub to `network.nix`:

```nix
machines.<hub> = {
  role = "hub";
  address = "<ip>";
  syncthingId = "..."; sshHostKey = "ssh-ed25519 ..."; deployKey = "ssh-ed25519 ...";
};
```

## 7. The hub's hardware configuration

Tell the user: the VPS's OS is replaced by the NixOS installer **in RAM only**;
the disk is not touched, and a reboot brings the provider's OS back. With their
yes:

```sh
git add -A    # nixos-anywhere evaluates the flake: it must see every file
nixod install-hub <hub> root@<ip> --stage hardware --yes
```

It writes `hosts/<hub>/hardware-configuration.nix` and adds it to git.

## 8. Check, build, commit, push

```sh
nix flake check
nix build --no-link .#nixosConfigurations.<name>.config.system.build.toplevel
nix build --no-link .#nixosConfigurations.<hub>.config.system.build.toplevel
git add -A
git status    # no `result` link, no stray file
git -c gpg.format=ssh -c user.signingkey="$HOME/.ssh/nixod_ed25519" commit -S -m "nixod: init"
git push origin main
```

The commit is signed by hand this once: this machine's git config signs by
itself after the switch.

## 9. Install the hub

Tell the user, plainly: **this wipes the VPS's disk.** With their explicit yes:

```sh
nixod install-hub <hub> root@<ip> --stage install --yes
```

It checks the staged identity matches `network.nix` (Syncthing ID, SSH host
key, deploy key) and the console password is staged, builds, adds the
read-only deploy key on GitHub, installs, reboots the VPS, deletes the
staging dir, and replaces the provider OS's host key with the hub's in
`~/.ssh/known_hosts`.

If it stops with "missing ...": the staged keys are gone (a logout or a
reboot). It prints the way out: a new hub identity, its public parts in
`network.nix`, a new signed commit, push, install again.

Once the VPS is back (a minute or two):
`ssh -i ~/.ssh/nixod_ed25519 root@<ip> nixod status` shows the init commit.

## 10. Switch this machine (the user), last

The switch changes the display manager, the desktop and often drivers: the
running session can't survive it. So the new system is made the boot
default, then the machine reboots. This ends your session. Before, tell the
user:

- after the reboot: log in, open a terminal (**Super+Return** with the
  starter's i3; say how in the user's own desktop), `cd` to the repo, start
  the agent again and say "resume the nixod setup";
- if the new system doesn't boot, pick the previous generation in the boot
  menu, and tell the agent what happened.

Then the user runs:

```sh
sudo nixos-rebuild boot --flake .#<name>
reboot
```

## 11. After the reboot

- `nixod status`: this machine runs the init commit, and the hub is among the
  Syncthing peers (it can take a minute).
- `ssh root@<hub> nixod status`: the hub runs the init commit.
- The key's passphrase: offer it. Without one, the key is protected only by
  the disk (encrypted or not: say which) and this user account. With one,
  the user unlocks it once per session (`ssh-add` in a terminal, or the first
  `ssh <hub>`), and until then you can't sign changes or log into the hub. To
  add it: `ssh-keygen -p -f ~/.ssh/nixod_ed25519`, in their terminal. The
  key stays the same: nothing to change in the repo.
- With a passphrase, offer one more step: a confirmation dialog each time the
  key is used (`nixod.home.ssh.confirm = true;` in `home/default.nix`). Every
  commit you sign and every login to the hub then waits for the user's click:
  a human check on what you do with the key. Without a passphrase it protects
  nothing (signing reads the key file directly). Then the user adds the key
  with `ssh-add -c`.
- Remind the user what keeps the network recoverable: the hub's console
  password and access to the provider account (`nixod doc recover`).

## Resuming

An init interrupted halfway (session lost, logout, crash).
`nixod init-status <name>` checks each step below against the repo and the
machines, and prints the step to continue at (`--offline` skips GitHub and
SSH; `--hub <hub>` while `network.nix` doesn't name the hub yet). The same
checks, by hand, in this order:

| Done when | Step |
|---|---|
| `gh auth status` works | 0 |
| no `NIXOD:FILL` left in `settings.nix`, `git config user.name` set | 1 |
| `hosts/<name>/` has `default.nix` and `hardware-configuration.nix` | 2 |
| `machines.<name>` is in `network.nix`, `~/.ssh/nixod_ed25519` exists | 3 |
| `ssh -i ~/.ssh/nixod_ed25519 -o BatchMode=yes root@<ip> true` works (or the hub is installed) | 4 |
| `hosts/<hub>/default.nix` and `disko.nix` exist | 5 |
| `machines.<hub>` is in `network.nix`, and `$XDG_RUNTIME_DIR/nixod/hub-<hub>/` holds the keys and `var/lib/nixod/console-password` (or the hub is installed) | 6 |
| `hosts/<hub>/hardware-configuration.nix` exists | 7 |
| `git status` is clean and `origin/main` has the init commit | 8 |
| `ssh root@<ip> nixod status` answers (the hub is installed) | 9 |
| `/etc/nixod/config` exists (this machine runs nixod) | 10 |

The hub's entry is in `network.nix` but the staging dir is gone, and the hub
isn't installed: make a new hub identity (step 6) and update its entry; if
the init commit was already pushed, commit and push the new entry (signed)
before step 9.
