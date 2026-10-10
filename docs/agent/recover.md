# recover: every machine lost, only the hub left

Mode: the user says every machine of the network is lost (or none can sign).
The hub still runs and holds the files. **Never reinstall the hub:** it would
wipe the only copy of the data.

The way back in is the hub's provider console (VNC/serial in the provider's
web panel), with the console password set at init.

1. On a new NixOS machine: GitHub login and clone, git identity, describe
   it, create its identity, as in a join (`nixod doc join`, steps 0 to 3).
   Add its entry to `network.nix`.
2. Commit it on `main`, signed with its own key:

   ```sh
   git add -A
   git -c gpg.format=ssh -c user.signingkey="$HOME/.ssh/nixod_ed25519" commit -S -m "nixod: recover with <name>"
   ```
3. The user opens the provider console, logs in with the console password,
   becomes root (`sudo -i`), and runs **there** (it refuses over SSH):

   ```sh
   nixod trust-once 'ssh-ed25519 AAAA... <this machine's userKey>'
   ```

   Give them the exact command to type. It trusts that key for one update only.
4. `git push origin main`. The hub applies it within minutes, and forgets the
   one-time key.
5. Switch this machine, as at the end of a join (`nixod doc join`, steps 6
   and 7: `nixos-rebuild boot`, then reboot). The folders come back from the
   hub.
6. Remove the lost machines (`nixod doc remove`), from this machine.
7. If the console password may have leaked, or the user wants a new one: it
   isn't in the repo, so it's changed on the hub itself:
   `ssh root@<hub> passwd <user>` (the user types it, in their terminal).
