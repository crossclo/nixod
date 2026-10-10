# join: add this machine to the network

Mode: this machine (`hostname`) is not in `network.nix`, which already has
machines. It runs NixOS. If it is in `network.nix` (on its `join/<name>`
branch) but doesn't run nixod yet (no `/etc/nixod/config`), an earlier join
was interrupted: see **Resuming** at the end.

`nixod` is not installed until the machine joins: here, `nixod ...` means
`nix run .#nixod -- ...`, run in the repo, and `gh ...` means
`nix run nixpkgs#gh -- ...`. If flakes aren't enabled yet, every `nix`
command needs `--extra-experimental-features "nix-command flakes"`.

Steps where the user types something (a login, a password) run **in a
separate terminal**: give them the exact command. `! <command>` gives no
terminal: don't use it for prompts. Passwords never go through the chat.

0. **GitHub and the clone** (the user, in a separate terminal):
   `nix run nixpkgs#gh -- auth login`: GitHub.com, **HTTPS**, yes to
   "Authenticate Git with your GitHub credentials". Then they clone the repo
   (it's private) **where `settings.repo.path` says** (`~/nixod` unless
   changed; every machine keeps it at the same place):
   `nix run nixpkgs#gh -- repo clone <user>/<repo> <path>`. `nixod join`
   refuses a clone elsewhere.
1. **Git identity, for this repo** (nixod's git config comes with the switch):
   `git config user.name "<settings.user.fullName>"` and
   `git config user.email "<settings.user.email>"`.
2. **Describe the machine:** `nixod doc describe-host` → `hosts/<name>/`.
3. **Its identity:** `nixod identity host <name>`. It makes this machine's own
   key, `~/.ssh/nixod_ed25519`, without a passphrase (the user can add one
   once the machine runs: see step 7). Add its entry to `network.nix`:
   `role = "host"`, `syncthingId`, `userKey`, and the folders the user chose
   (describe-host step 5; a new folder also needs its entry in `folders`).
4. **Send the join request:** `nixod join <name>`. It builds the machine,
   commits network.nix and
   `hosts/<name>/` on a branch `join/<name>`, pushes it and opens a pull
   request. GitHub's CI checks that every machine still evaluates.

   A join request changes `network.nix` and `hosts/<name>/` only. Changes to
   shared files (`home/`, other hosts) go in their own commit later, from a
   trusted machine: the review flags them.
5. **Tell the user** to ask their agent on a trusted machine to review and
   approve it (`nixod doc review`), and to come back once it's approved.
6. **After the approval:** the hub accepts this machine within minutes. The
   switch changes the desktop (and often drivers): the running session can't
   survive it, so the new system becomes the boot default and the machine
   reboots, which ends your session. Before, tell the user: after the
   reboot, Super+Return opens a terminal (start the agent again in the repo
   for step 7); if the new system doesn't boot, pick the previous generation
   in the boot menu. Then the user runs:

   ```sh
   git switch main && git pull
   sudo nixos-rebuild boot --flake .#<name>
   reboot
   ```
7. **After the reboot:** `nixod status` shows the hub among the Syncthing
   peers, and the folders start arriving. From now on, updates come with
   `nixod update`. Offer a passphrase for the key, as in `nixod doc init`
   (step 11): `ssh-keygen -p -f ~/.ssh/nixod_ed25519`, in their terminal, and
   then the user unlocks it once per session (`ssh-add`).

## Resuming

Continue at the first step that isn't done: `gh auth status` works (0);
`git config user.name` is set (1); `hosts/<name>/` has `default.nix` and
`hardware-configuration.nix` (2); `machines.<name>` is in `network.nix` and
`~/.ssh/nixod_ed25519` exists (3); the `join/<name>` branch is on GitHub (4);
it is merged into `main` (5, waiting for the trusted machine);
`/etc/nixod/config` exists (6).
