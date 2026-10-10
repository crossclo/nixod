# change: everyday changes

Mode: this machine is in the network and the user wants something changed (a
package, a setting, a folder, newer packages).

Changes go through the repo, never by hand on a machine. Commits are signed by
this machine's key (git does it): the hub and the other hosts only apply signed
commits.

1. **Pull first:** `git pull` (on `main`, clean tree).
2. **Edit:**
   - one machine: `hosts/<name>/`; every host's user setup: `home/`;
   - a synced folder: in `network.nix`, under `folders` and in each machine's
     entry that should have it;
   - newer packages: `nix flake update` (everything) or `nix flake update
     nixpkgs`; a newer nixod: `nix flake update nixod`.
3. **Build** every machine the change touches, at least this one, and the hub
   whenever `network.nix` or `flake.lock` changes:
   `nix build --no-link .#nixosConfigurations.<name>.config.system.build.toplevel`.
   `nix flake check` evaluates them all.
4. **Commit and push:** `git commit -am "..."` then `git push`.
5. **Apply here:** `nixod update` (verifies, then `nixos-rebuild switch`).
   The hub applies it on its own; the other hosts get a notification and run
   `nixod update` when it suits them.

`nixod status` shows the running commit, the hub's last update and the Syncthing
peers. If the hub rejected an update (`ssh root@<hub> nixod status`), the reason
is there: an unsigned commit (push a signed one on top, which vouches for what
is under it: `git commit --allow-empty -S -m "sign"`), or a rewritten history
(never force-push `main`; never amend a pushed commit).
