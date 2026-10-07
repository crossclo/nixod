# join: add this machine to the network

Mode: this machine (`hostname`) is not in `network.nix`, which already has
machines. It runs NixOS, and the user has cloned their repo (`gh auth login`
first: it is private).

`nixod` is not installed until the machine joins: here, `nixod ...` means
`nix run .#nixod -- ...`, run in the repo. If flakes aren't enabled yet, every
`nix` command needs `--extra-experimental-features "nix-command flakes"`.

1. **Describe the machine:** `nixod doc describe-host` → `hosts/<name>/`.
2. **Its identity:** the user runs `! nix run .#nixod -- identity host <name>`
   (or `nixod identity host <name> --no-passphrase`). Add its entry to
   `network.nix`: `role = "host"`, `syncthingId`, `userKey`, `folders`.
3. **Send the join request:** `nixod join <name>`. It builds the machine,
   commits network.nix and
   `hosts/<name>/` on a branch `join/<name>`, pushes it and opens a pull
   request. GitHub's CI checks that every machine still evaluates.

   A join request changes `network.nix` and `hosts/<name>/` only. Changes to
   shared files (`home/`, other hosts) go in their own commit later, from a
   trusted machine: the review flags them.
4. **Tell the user** to ask their agent on a trusted machine to review and
   approve it (`nixod doc review`), and to come back once it's approved.
5. **After the approval:** the hub accepts this machine within minutes. Then:

   ```sh
   git switch main && git pull
   sudo nixos-rebuild switch --flake .#<name>
   ```

   The folders start arriving. From now on, updates come with `nixod update`.
