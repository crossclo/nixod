# nixod: instructions for the agent

This repo describes the user's whole network: every machine's system, desktop,
dotfiles and synced folders, and the VPS (the hub) that keeps them in sync.
What nixod is and how it works: https://github.com/crossclo/nixod (README).

## Tools

- `nixod <command>`: the helper. On a machine not yet running nixod, run it as
  `nix run .#nixod -- <command>` from this repo (it uses the version the repo
  pins). Add `--extra-experimental-features "nix-command flakes"` to `nix` if
  flakes aren't enabled yet.
- `nixod doc <playbook>`: the step-by-step playbooks below, for this version.
  Read the playbook before starting; follow it in order.

## Which mode

Look at `network.nix` and this machine's name (`hostname`):

| Situation | Playbook |
|---|---|
| `network.nix` has no machines | `init` (it uses `describe-host` and `hub`) |
| this machine is not in `network.nix` | `join` (it uses `describe-host`) |
| this machine is in `network.nix`, as its only host, but doesn't run nixod yet (no `/etc/nixod/config`): an interrupted init | `init` (its "Resuming" section) |
| this machine is in `network.nix` with other hosts, but doesn't run nixod yet: an interrupted join | `join` (its "Resuming" section) |
| the user asks to review / approve a join request | `review` |
| the user wants something changed on their machines | `change` |
| the user wants a machine out (lost, sold, broken) | `remove` |
| every machine is lost, only the hub is left | `recover` |

## Never, whatever the case

- **Never commit a private key**, or put one anywhere in the repo.
- **Never wipe a disk without the user's explicit yes** in this conversation.
  **Never reinstall a hub that holds data**: it may hold the only copy.
- **Never skip, weaken or work around update verification** (signatures,
  fast-forward checks, `allowed_signers`). Never force-push `main`.
- **Change machines through this repo**, never by hand on a machine. The only
  exception is `nixod trust-once` on the hub's provider console (`recover`).
- **Build before asking the user to switch.**
- **Secrets stay out of the chat**: passwords and passphrases are typed by the
  user, in a separate terminal, never by you. Give them the exact command.
  (`! <command>` in Claude Code may not give a real terminal: don't use it for
  anything that prompts.)

## How to work (adaptable)

- Use the `nixod` commands for identities, installs, joins, reviews and removals.
  Each is a short script of named steps; `--dry-run` shows them. If a case
  doesn't fit (an unusual VPS, disk layout or GitHub setup), read the script,
  run or adapt its steps by hand, and tell the user what you did differently
  and why. If the fix is general, suggest it upstream to nixod.
- Ask the user before anything they would want to decide: which folders to
  sync, which profiles to enable, what to bring over from their old config.
- Commits are signed, and the hub is reached, with this machine's key
  `~/.ssh/nixod_ed25519`. If signing or `ssh <hub>` fails because the key has a
  passphrase and isn't loaded, ask the user to run `ssh-add
  ~/.ssh/nixod_ed25519` in their terminal (once per session), then retry.
- Everything nixod's modules set is a default. Override in `home/` or
  `hosts/<name>/`; don't copy nixod's modules into this repo.
