# Known issues

nixod is in test phase. This file lists what is known to be wrong, missing or
untested, so it can be fixed before the first real install.

Sources:
- a **paper walkthrough of `init`** (2026-10-07): a fresh agent, with only
  `template/`, the README, the playbooks (`docs/agent/`) and the code, played a
  user's agent through a whole setup and checked every step against the
  scripts and modules (nothing was run);
- what was found while building nixod (phases 1 to 6);
- the review of the walkthrough's fixes (2026-10-10).

---

## Fixed

What the walkthrough found, and how it was fixed. Every check passes, the
VM tests included (CI run 38084260057, one runner per VM test).

| | Issue | Fix |
|---|---|---|
| B1 | Signed init commit fails with a passphrase key | Each machine gets its own key, `~/.ssh/nixod_ed25519`, without a passphrase by default (`--passphrase` to ask); the user may add one at the end (`ssh-keygen -p`, same key) and unlock it per session. The same key logs into the VPS (probe, install-hub) and the hub (`ssh <hub>` uses it through `/etc/ssh/ssh_config`). `network.nix` refuses a `userKey` used by two machines. |
| B2 | Hub keys lost at logout/reboot before the install | The hub is installed before the first switch; "no logout, no reboot" is said where it matters; `install-hub` checks all three staged keys against `network.nix` and prints the way out when the staging dir is gone. |
| B3 | `result` link committed | `template/.gitignore`, `--no-link` in the playbooks, a check. |
| B4 | `settings.repo.path` never set | Init step 1 sets it; `nixod join` refuses a clone elsewhere. |
| B5 | `gh` not installed or logged in | Step 0 in init and join: `nix run nixpkgs#gh -- auth login`, HTTPS. |
| P1 | No git identity before the switch | `git config user.name/user.email` for the repo, at init, join, recover. |
| P2 | SSH to the VPS not prepared | Init step 4: the user checks the host key and runs `ssh-copy-id`; the agent checks with `BatchMode`. `probe` uses `BatchMode` and the nixod key. |
| P3 | `!` may not give a terminal | Checked: it doesn't (`! tty` prints "not a tty"). Prompts run "in a separate terminal"; the docs say not to use `!` for them. |
| P4, P9 | No way to resume an interrupted init | An AGENTS.md row and a "Resuming" table in `init` (and `join`), from what the repo and the machine show. |
| P5 | DHCP test wrong | `hub.md` decides IPv4 and IPv6 separately, ignores link-local, leaves SLAAC to the kernel, covers the on-link gateway (/32). |
| P6 | First switch kills the session | `nixos-rebuild boot` and a reboot, as the last step; the user is told how to open a terminal in i3 and how to boot the previous generation. |
| P7 | VPS memory and arch not checked | `hub.md` checks `memoryKiB` and `arch` first. |
| P8 | Console password hash in the repo | Out of the repo: `nixod identity hub --console-password` stages a yescrypt hash, installed as `/var/lib/nixod/console-password` (`hashedPasswordFile`); `install-hub` refuses without it. |
| P10 | Old display manager ported next to greetd | `describe-host` says not to; `desktop-i3` asserts no other display manager is on. Boot-loader advice follows the machine's boot loader. |
| P11 | Hardware config visibility | `install-hub --stage hardware` adds the file to git itself. |
| M1–M10 | Minor | AGENTS.md wording (M1); folders asked in the identity step (M2); `$HOME` in the signing key path (M3); `keyboard.xkbVariant` (M4); `extraLocaleSettings` copied (M5); versioning asked, with the options (M6); existing `home.stateVersion` kept (M7); probe's kernel modules not copied (M8); `flake.lock` committed (M9); `nofail` in `hosts/<name>/default.nix` (M10). |
| T6 | Syncthing global discovery | Decided: global discovery and relays off, local discovery on. |
| O1 | nixos-25.11 out of support | Moved to 26.05 (nixpkgs, Home Manager, renamed options). |
| O2 | syncthing uid hard-coded | Read from the hub's config; 237:237 only as a fallback with `--store-paths`. |
| O3 | Framework CI on demand only | Every push runs all checks but the VM tests; VM tests stay on demand. |
| O4 | Review doesn't flag changes inside `network.nix` | `nixod review` lists the new machine's folders and warns about any changed entry or folder option; README says the review is the boundary. |
| P4 | (deferred) `nixod init-status` | Done (2026-10-11): checks every init step against the repo, the staging dir, GitHub and the VPS, prints the step to continue at; `--offline`. Tested offline in `tests/cli.nix`. |
| P5, P7 | (deferred) probe summary and warnings | Done (2026-10-11): `probe` adds a `summary` computed locally by `probe-summary.jq` (IPv4/IPv6 method, gateway outside the subnet, disk, warnings for memory, arch, several disks); `--from-json` re-summarizes a saved probe. Tested on two sample probes. |
| — | (deferred) confirmation for each use of the key | Done (2026-10-11): `nixod.home.ssh.confirm` (`AddKeysToAgent confirm`, x11-ssh-askpass, the ssh-agent started in the graphical session). Only useful with a passphrase. Evaluated in the checks, never run on a desktop (see T5). |
| N1 | (new) A machine that is behind rejected commits signed by machines that joined since, and accepted ones signed by machines removed since | Trust follows the history: each signed commit that changes `network.nix` updates the trusted keys for the commits after it (`verify` in `lib.sh`, tested in `tests/update.nix`). |

---

## Still open

Nothing: the deferred items are done (see below).

---

## Not tested yet

Everything below passed its tests in VMs only partly, or not at all. It runs
for the first time on real machines.

### T1. `nixos-rebuild switch` after an update

In the VM tests for updates and joins, the final `nixos-rebuild switch` is
replaced by a stand-in that records the commit: a VM has no internet to build
a system with. Fetching, verifying, fast-forwarding and calling the switch are
real; the switch itself, inside `nixod-update.service` on the hub (with
`restartIfChanged = false`), has never run.

### T2. kexec (`install-hub --stage hardware`)

The hub install was tested on a VM with an empty disk, without kexec (it
downloads an installer image from the internet). The hardware stage, and the
install stage's kexec, come straight from nixos-anywhere, which tests them
itself, but not with nixod's flake.

### T3. GitHub's side

Never run: `gh pr create` (`nixod join`), fetching a request by PR number
(`refs/pull/<n>/head`), GitHub marking the PR merged after `nixod approve`,
`gh repo deploy-key add` (`install-hub`), and the template's CI workflow on a
real instance repo.

### T4. `nixod probe` on a real VPS

Only tested in `--dry-run`. Its JSON is built by hand in shell
(`probe-remote.sh`) and has never been parsed from a real distribution's
output.

### T5. The desktop

The host modules (i3, greetd, Home Manager profiles) are evaluated in the
checks (`eval-host`) but never built and never booted. The VM tests use hosts
without a desktop. That includes `nixod.home.ssh.confirm`: whether the
ssh-agent, started with the graphical session, gets DISPLAY and shows the
dialog is unverified.

### T6. Syncthing between real hosts

With global discovery and relays off, hosts reach each other through the hub
(fixed address) or directly on the same LAN. Not yet seen on real networks
(NAT, a laptop away from home).
