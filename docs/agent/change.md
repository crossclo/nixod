# change: everyday changes

Mode: this machine is in the network and the user wants something changed (a
package, a setting, a folder, newer packages).

Changes go through the repo, never by hand on a machine. Commits are signed by
this machine's key (git does it): the hub and the other hosts only apply signed
commits. A signed commit vouches for its whole tree, including whatever is
under it: never sign on top of commits nobody verified.

1. **Check, then pull:** `nixod check` first. "up to date" or "ready": go on
   with `git pull` (on `main`, clean tree). **"rejected"**: stop. GitHub has
   commits no trusted machine signed; see "A rejected update" below before
   anything else.
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
peers.

## A rejected update

`nixod check` (or the hub: `ssh root@<hub> nixod status`) says why:

- **A rewritten history**: someone force-pushed `main`. Never force-push it
  back without the user; tell them, and find out who did it.
- **Not signed by a trusted machine**: commits on GitHub that no machine of the
  network signed. Maybe the user's own (made on a machine without nixod, or
  with signing off), **maybe someone else's** (a GitHub account taken over).
  Signing anything on top would make every machine apply them, so:
  1. Show the user exactly what they change, from the running commit:
     `git log --format='%h %G? %an %s' <running>..origin/main` and
     `git diff <running> origin/main` (`nixod status` shows `<running>`).
  2. If the user reads it and says it is theirs and wanted: sign on top
     (`git pull`, then `git commit --allow-empty -S -m "nixod: vouch for ..."`,
     push). `nixod approve` and `nixod remove` refuse until then.
  3. If not: undo it in a signed commit, so the tip's tree is the running one
     again: `git pull`, `git read-tree --reset -u <running>`, check
     `git diff <running>` is empty, `git commit -S -m "nixod: undo unverified
     commits"`, push. Tell the user to secure their GitHub account.
