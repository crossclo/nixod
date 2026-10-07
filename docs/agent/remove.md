# remove: remove a machine (lost, sold, broken)

Mode: the user asks to remove a machine. Run it on another machine already in
the network. The hub can't be removed.

1. Confirm with the user which machine, and that they want it out for good.
2. Delete its entry from `machines` in `network.nix`.
3. `nixod remove <name>`: checks the entry is gone, deletes `hosts/<name>/`,
   builds the hub, commits (signed) and pushes.
4. Once the hub applies it, the machine can no longer sync, log into the hub,
   or sign updates. Its folders stay on the hub and the other machines.
5. Tell the user to also revoke the machine's GitHub access (its SSH key in
   GitHub's settings, its `gh` login): it can still read the repo otherwise.
