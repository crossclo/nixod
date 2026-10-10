# remove: remove a machine (lost, sold, broken)

Mode: the user asks to remove a machine. Run it on another machine already in
the network. The hub can't be removed.

1. Confirm with the user which machine, and that they want it out for good.
   Not this machine, and not the last host (nobody could sign any more).
2. Catch up first: `nixod check`, then `git merge --ff-only origin/main` (see
   `nixod doc change`, step 1, and what to do when the check rejects).
3. Delete its entry from `machines` in `network.nix`.
4. `nixod remove <name>`: checks the entry is gone and `main` is GitHub's,
   deletes `hosts/<name>/`, builds the hub, commits (signed) and pushes. If the
   push is refused, it says how to retry.
5. Once the hub applies it, the machine can no longer sync, log into the hub,
   or sign updates. Its files stay on the other machines and on the hub's
   disk; a folder only this machine had is no longer synced (its copy on the
   hub stays, unsynced).
6. Tell the user to also revoke the machine's GitHub access (its SSH key in
   GitHub's settings, its `gh` login): it can still read the repo otherwise.
