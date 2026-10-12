# Known issues

nixod is in test phase. This file lists what is known to be wrong, missing or
untested, so it can be fixed before the first real install.

Sources:
- a **paper walkthrough of `init`** (2026-10-07): a fresh agent, with only
  `template/`, the README, the playbooks (`docs/agent/`) and the code, played a
  user's agent through a whole setup and checked every step against the
  scripts and modules (nothing was run);
- what was found while building nixod (phases 1 to 6);
- the review of the walkthrough's fixes (2026-10-10);
- a second paper review of every flow by a fresh agent (2026-10-11); its
  report stopped after its third finding (R1–R3 below), the rest was lost;
- a third review, on correctness and usability (2026-10-11): Q1–Q13, q1–q13
  below.

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
| P10 | Old display manager ported next to greetd | `describe-host` says not to; the `x11` profile (was `desktop-i3`) asserts no other display manager is on. Boot-loader advice follows the machine's boot loader. |
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
| R1 | Signing on top of unverified commits: `approve`, `remove`, a `change` commit, the recovery commit, and the old "sign on top" advice all vouched for whatever was on `main`, turning a GitHub takeover into a signed update | `approve` and `remove` refuse unless what they sign on top of verifies (`check_base`); `change` runs `nixod check` before `git pull`, and a rejected update is shown to the user (accept explicitly, or undo it in a signed commit); `recover` compares `main` with the hub's running commit first. A new host's first build goes through `nixod update --first <name>`, which verifies the approval against its own join request's `network.nix`. |
| R2 | `nixod review` evaluated the request's `network.nix` as plain Nix: it could read local files (the nixod key) and send them out | The request's `network.nix` is evaluated alone in an empty directory, in restricted mode (no file reads, no fetches, no search path, no import from derivation); `network.nix` must be plain data. |
| R3 | `trust-once` refused every pseudo-terminal, and `sudo -i` (the documented way to become root on the console) runs on one: recovery couldn't complete | It checks the login session instead (logind's `Remote=no`, kept through sudo). The VM test now does the documented path: login on tty1, `sudo -i`, `nixod trust-once`; and checks a service without a session is refused. |
| Q1 | No working way to create the instance repo ("Use this template" copies the framework) | README gives the commands (`git init -b main`, `nix flake init -t`, `gh repo create --private`). |
| Q2 | The trust-once key was used up by any failing check, before the recovery commit arrived | Used up only by a commit signed by it; others leave it waiting; unused, it expires after a day. Recovery pushes its commit first. |
| Q3 | A whole public key typed by hand on a VNC console | `nixod trust-once --from <name>` reads it from the pushed commit and shows the fingerprint to compare. Tested in the VM, as documented (tty1 login, `sudo -i`). |
| Q4 | Dotfiles written to `home/` in a join are missing from the request | In a join or recovery, only `hosts/<name>/home.nix`; shared changes later, in a `change`. |
| Q5 | `nixod update` (sudo) given to the agent | Marked as the user's step, in a terminal (change, recover). |
| Q6 | `git commit -am` misses new files | `git add -A`, `git status`, commit; what to do when the push is refused. |
| Q7 | `init-status --offline` after the install sent the user back to step 6 (new hub keys) | Offline with no staging dir: "unknown, the hub may be installed". |
| Q8 | NVIDIA advice wrong for Maxwell/Pascal/Volta on 26.05 (current driver dropped them) | `legacy_580` for those; `stable` + `open = true` for Turing and newer. |
| Q9 | The machine's name defaulted to `hostname` (often `nixos`) | AGENTS.md: the name is the one in `network.nix`/`hosts/`; ask when it may differ. |
| Q10 | Reinstalling a machine under the same name had no path | AGENTS.md row and README: remove it from another machine, then join again. |
| Q11 | No instructions for a join request that conflicts | join.md: merge `origin/main` into `join/<name>`, fix, `nixod join` again, review again. |
| Q12 | `nixod remove` retry after a refused push didn't work; no catch-up first | remove.md catches up first; `remove` refuses unless `main` is GitHub's, and gives the real retry. |
| Q13 | `approve`/`join` printed outdated next steps | Both print `update --first <name>`, then reboot. |
| q1–q13 | Minor | AGENTS row after the first reboot; `approve` resets after a refused push; existing Syncthing config not ported; probe saved outside the repo; flakes flag in commands handed to the user; `ssh -t` for `passwd`; `remove` refuses this machine and the last host; remove.md on what happens to folders; review.md on building the request vs the merge; README CI wording; moving to a new VPS vs reinstalling; PLAN drift; sudo-user providers. Also: `check_base` with no running revision requires the base to be signed; change.md fast-forwards to the verified commit instead of `git pull`. |
| S1 | nixos-anywhere connected with host key checking off, so the key checked at init step 4 was never enforced during the install | `install-hub` pins it: nixos-anywhere runs behind an `ssh` that puts `StrictHostKeyChecking=yes` and the VPS's entries from `~/.ssh/known_hosts` first (ssh keeps the first value of an option; `nix copy` and `ssh-copy-id` go through it too). The kexec installer keeps the provider OS's host keys, so the same key holds before and after the kexec. `install-hub` refuses when the key is unknown, and tries one connection first, since nixos-anywhere would retry a mismatch forever. VM-tested: unknown key and wrong key refused. |
| V1 | (dogfood, 2026-10-12) Neovim aborted at startup on every instance (nvim-treesitter's `configs` module is gone), and the user couldn't fix it: the config was a framework store path | PLAN section 10: shell, editor and desktop moved to `starter/`, plain files copied into the instance (`nixod starter`), which owns them; the framework keeps the wiring (git signing, ssh-agent, `x11`, the network). The starter's Neovim starts treesitter per buffer; the `starter-neovim` check starts it headless and fails on any error. |
| N1 | (new) A machine that is behind rejected commits signed by machines that joined since, and accepted ones signed by machines removed since | Trust follows the history: each signed commit that changes `network.nix` updates the trusted keys for the commits after it (`verify` in `lib.sh`, tested in `tests/update.nix`). |

---

## Still open

Nothing known. What is left is testing on real machines (below).

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

The host modules (`x11`, greetd) and the starter files (i3, the Home Manager
files) are evaluated in the checks (`eval-host`) but never built and never
booted (the starter's Neovim config is the exception: `starter-neovim` runs
it). The VM tests use hosts
without a desktop. That includes `nixod.home.ssh.confirm`: whether the
ssh-agent, started with the graphical session, gets DISPLAY and shows the
dialog is unverified.

### T6. Syncthing between real hosts

With global discovery and relays off, hosts reach each other through the hub
(fixed address) or directly on the same LAN. Not yet seen on real networks
(NAT, a laptop away from home).
