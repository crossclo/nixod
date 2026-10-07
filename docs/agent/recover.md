# recover: every machine lost, only the hub left

Mode: the user says every machine of the network is lost (or none can sign).
The hub still runs and holds the files. **Never reinstall the hub:** it would
wipe the only copy of the data.

The way back in is the hub's provider console (VNC/serial in the provider's
web panel), with the console password set at init.

1. On a new NixOS machine, with the repo cloned: describe it
   (`nixod doc describe-host`) and create its identity, as in a join
   (`nixod doc join`, steps 1 to 3). Add its entry to `network.nix`.
2. Commit it on `main`, signed with its own key:

   ```sh
   git add -A
   git -c gpg.format=ssh -c user.signingkey=~/.ssh/id_ed25519 commit -S -m "nixod: recover with <name>"
   ```
3. The user opens the provider console, logs in with the console password,
   becomes root (`sudo -i`), and runs **there** (it refuses over SSH):

   ```sh
   nixod trust-once 'ssh-ed25519 AAAA... <this machine's userKey>'
   ```

   Give them the exact command to type. It trusts that key for one update only.
4. `git push origin main`. The hub applies it within minutes, and forgets the
   one-time key.
5. Switch this machine: `sudo nixos-rebuild switch --flake .#<name>`. The
   folders come back from the hub.
6. Remove the lost machines (`nixod doc remove`), from this machine.
