# init: set up the network (first host + hub)

Mode: `network.nix` has no machines. You are on the user's first machine,
which already runs NixOS, in a clone of their **private** instance repo.

You need from the user: a VPS reachable as `root@<ip>` over SSH (any provider,
stock OS), a GitHub account (`gh auth status` works), and answers to a few
questions. Expect the whole flow to take an hour, most of it builds.

Until this machine runs nixod, `nixod` is not installed: in this playbook,
`nixod ...` means `nix run .#nixod -- ...`, run in the repo (it uses the
framework version the repo pins). If flakes aren't enabled yet, every `nix`
command needs `--extra-experimental-features "nix-command flakes"`.

## 1. Settings

Fill every `NIXOD:FILL` in `settings.nix` (`grep -n NIXOD:FILL settings.nix`):

- `user.name`, `user.fullName`, `user.email`: ask. Default `user.name` to the
  current login (`id -un`).
- `timeZone`, `keyboard.console`, `keyboard.xkb`: read them from the current
  system (`timedatectl`, `/etc/nixos/configuration.nix`), confirm with the user.
- `repo.url`: the SSH form, `git@github.com:<user>/<repo>.git` (the hub fetches
  with a deploy key, over SSH).
- `hub.hashedPassword`: the hub's console password. The password must never
  appear in the chat: ask the user to run, in their own terminal,
  `! nix shell nixpkgs#mkpasswd -c mkpasswd -m sha-512`, and paste the hash.
  Tell them to keep the password: with every machine lost, it is the way back
  in (`nixod doc recover`).

## 2. Describe this machine

Follow `nixod doc describe-host`. Result: `hosts/<name>/`, with
`hardware-configuration.nix` generated on this machine.

## 3. This machine's identity

The SSH key may get a passphrase, so the user runs it:
`! nix run .#nixod -- identity host <name>`
(Or, if the user doesn't want a passphrase: `nixod identity host <name> --no-passphrase`.)

It prints `syncthingId` and `userKey`. Add the machine to `network.nix`:

```nix
machines.<name> = {
  role = "host";
  syncthingId = "...";
  userKey = "ssh-ed25519 ...";
  folders = { docs = "/home/<user>/sync/docs"; };   # folder name → path here
};
folders.docs = { versioning = { type = "staggered"; params.maxAge = "31536000"; }; };
```

## 4. Look at the VPS

`nixod probe root@<ip>` prints JSON (read-only). Write `hosts/<hub>/default.nix`
and `hosts/<hub>/disko.nix` from it: `nixod doc hub`. Ask the user for the hub's
name (default `hub`).

## 5. The hub's identity

`nixod identity hub <hub>` (keys go to a tmpfs staging dir, never the repo).
Add it to `network.nix`:

```nix
machines.<hub> = {
  role = "hub";
  address = "<ip>";
  syncthingId = "..."; sshHostKey = "ssh-ed25519 ..."; deployKey = "ssh-ed25519 ...";
};
```

## 6. The hub's hardware configuration

Tell the user: the VPS's OS is replaced by the NixOS installer **in RAM only**;
the disk is not touched, and a reboot brings the provider's OS back. With their
yes:

```sh
git add -A    # nixos-anywhere evaluates the flake: it must see every file
nixod install-hub <hub> root@<ip> --stage hardware --yes
```

It writes `hosts/<hub>/hardware-configuration.nix`.

## 7. Check, build, commit, push

```sh
nix flake check
nix build .#nixosConfigurations.<name>.config.system.build.toplevel
nix build .#nixosConfigurations.<hub>.config.system.build.toplevel
git add -A
git -c gpg.format=ssh -c user.signingkey=~/.ssh/id_ed25519 commit -S -m "nixod: init"
git push origin main
```

The commit is signed by hand this once: this machine's git config signs by
itself after the switch.

## 8. Switch this machine (the user)

The user runs `sudo nixos-rebuild switch --flake .#<name>`. Their desktop,
dotfiles and folders are now in place; Syncthing waits for the hub.

## 9. Install the hub

Tell the user, plainly: **this wipes the VPS's disk.** With their explicit yes:

```sh
nixod install-hub <hub> root@<ip> --stage install --yes
```

It checks the staged identity matches `network.nix`, builds, adds the read-only
deploy key on GitHub, installs, reboots, and deletes the staging dir.

## 10. Check

- `nixod status` on this machine: the hub shows in the Syncthing peers.
- `ssh root@<ip> nixod status`: the hub runs the init commit.

Then remind the user what keeps the network recoverable: the hub's console
password and access to the provider account (`nixod doc recover`).
