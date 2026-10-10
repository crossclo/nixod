# recover: every machine lost, only the hub left

Mode: the user says every machine of the network is lost (or none can sign).
The hub still runs and holds the files. **Never reinstall the hub:** it would
wipe the only copy of the data.

The way back in is the hub's provider console (VNC/serial in the provider's
web panel), with the console password set at init.

1. On a new NixOS machine: GitHub login and clone, git identity
   (`nixod doc join`, steps 0 and 1).
2. **What the hub runs** (the user, on the provider console): log in as the
   user with the console password, become root (`sudo -i`), run `nixod
   status`, and read you the `running` commit. Ask them to keep the console
   open: they come back to it at step 5.
3. **Compare** with GitHub: `git fetch origin`, then `git log --format='%h
   %G? %an %s' <running>..origin/main`.
   - Nothing: `main` is what the hub runs. Go on.
   - Commits: nobody the hub trusts signed them (every machine is lost).
     Your recovery commit will vouch for its whole tree, so show the user
     `git diff <running> origin/main`. Keep them only if the user reads them
     and says they are theirs. Otherwise undo them now: `git read-tree
     --reset -u <running>` (the files go back to the running commit; your
     commit will carry the undo).
4. Describe this machine and create its identity, as in a join (`nixod doc
   join`, steps 2 and 3). Add its entry to `network.nix`.
5. The user, back on the console as root, runs **there** (it refuses over
   SSH, and outside a console login):

   ```sh
   nixod trust-once 'ssh-ed25519 AAAA... <this machine's userKey>'
   ```

   Give them the exact command to type. It trusts that key for the next
   update only.
6. Commit on `main`, signed with this machine's own key, and push:

   ```sh
   git add -A
   git diff --cached --stat <running>   # only this machine's files (and the undo, if any)
   git -c gpg.format=ssh -c user.signingkey="$HOME/.ssh/nixod_ed25519" commit -S -m "nixod: recover with <name>"
   git push origin main
   ```

   The hub applies it within minutes, and forgets the one-time key.
7. Switch this machine: `nixos-rebuild boot --flake .#<name>` (sudo), then
   reboot, as at the end of a join. The folders come back from the hub.
8. Remove the lost machines (`nixod doc remove`), from this machine.
9. If the console password may have leaked, or the user wants a new one: it
   isn't in the repo, so it's changed on the hub itself:
   `ssh root@<hub> passwd <user>` (the user types it, in their terminal).
