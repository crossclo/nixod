# nixod: Nix One Desktop

**The same system, the same files, on every machine you own.**

nixod is a NixOS template that gives every machine you own the same configuration
and the same synced folders. A VPS that is always on keeps them in sync. You don't
fill in the template by hand: your AI agent reads `AGENTS.md`, looks at your
hardware and your existing config, and writes your setup for you. All you do is
answer a few questions and rebuild.

> Status: design phase. This README describes how the system works, not what is
> built yet.

---

## The idea

- **One repo describes everything.** Every machine is in it: its system, its
  desktop, its dotfiles, its synced folders, even the VPS disk layout. Nothing is
  configured by hand. If a machine dies, you rebuild it from the repo.
- **Your files follow you.** Folders like `projects`, `docs` or `keepass` are synced
  between all your machines with Syncthing. The VPS is always online, so two
  machines that are never on at the same time still stay in sync.
- **The network is closed.** A machine only joins if a machine you already trust
  approves it. The repo holds the list of approved machines.
- **Your agent does the setup.** The template contains no personal data. Your agent
  fills it in: your user, your keys, your hardware, your existing dotfiles.

---

## The pieces

### Machines

| Role | What it is | Example |
|---|---|---|
| **Hub** | The VPS: always on, reachable from the internet, the meeting point for all sync traffic. Has no desktop. | `vps` |
| **Host** | Your real machines (desktop, laptop): full desktop, your dotfiles, your synced folders. | `tower`, `laptop` |

Every host syncs **through the hub**. Two hosts on the same network can also talk
directly, but they don't need to. When a new machine joins, only the hub has to
know about it right away.

### Tools

| Tool | Used for |
|---|---|
| **NixOS + flakes** | Describing each machine and rebuilding it the same way every time |
| **Home Manager** | Your user setup: shell, editor, desktop, dotfiles |
| **Syncthing** | Syncing your folders between machines, peer to peer and encrypted |
| **nixos-anywhere + disko** | Installing NixOS on the VPS over SSH, disk layout included, whatever OS the provider started with |
| **Git + GitHub** | Where the config lives, where join requests arrive (pull requests), and where changes are checked (GitHub Actions) |
| **SSH commit signing** | Proving a change comes from one of your trusted machines |
| **Auto-upgrade** | Every machine fetches the repo on a schedule and applies new changes |
| **Your AI agent + `AGENTS.md`** | Doing the setup: reading hardware, writing config, creating keys, running the installs |

### The list of machines

One file in the repo, `network.nix`, lists every machine in your network: its name,
its role, its Syncthing ID, its public SSH key, and the folders it wants.

Everything about how machines know each other is built from this list:

- who Syncthing accepts and shares each folder with,
- which SSH keys may log into the VPS,
- which machines may sign changes.

**Adding a machine means adding one entry. Removing one means deleting it.**

### Trust

A change is applied only if its commit was **signed by a machine in the list**.
Every machine checks the signature before applying anything. So if someone takes
over your GitHub account, they still cannot push a config to your machines. Only
your machines can approve changes.

---

## Flow 1: Setting up your network

You do this once, from your first machine. That machine must already run NixOS.

**You need:** a machine running NixOS, a fresh VPS from any provider (root SSH
access to its stock Linux), and a GitHub account.

1. **Create your repo.** Make a **private** copy of this template on GitHub and
   clone it onto your first machine.
2. **Start your agent** in the repo and tell it: *"This is the setup of my nixod
   network."* It reads `AGENTS.md` and follows the setup steps.
3. **The agent describes your first machine:**
   - generates the machine's **NixOS hardware configuration** (required, always
     the first step),
   - looks at the hardware to pick the right options: graphics card driver
     (NVIDIA), laptop features (battery, touchpad), dual boot, extra disks,
   - reads your current NixOS config and your existing dotfiles (on the machine
     or in your GitHub repos) and brings them into the template; anything it
     doesn't find comes from the template defaults,
   - asks you the basics: user name, time zone, keyboard, which folders to sync.
4. **The agent looks at the VPS before wiping it.** It logs into the provider's
   stock system and notes the network settings, the disk, and how it boots. It
   then starts the NixOS installer in the VPS's memory, without touching the
   disk yet, to generate the VPS's hardware configuration.
5. **The agent creates the identities in advance,** for both your machine and the
   VPS: the Syncthing IDs and the SSH keys. Both machines go into `network.nix`
   already knowing each other, so you don't have to come back and fix anything.
6. **The agent commits** the setup, signed with your machine's key.
7. **You rebuild your first machine.** Your desktop, dotfiles and folders are now
   in place. Syncthing waits until the VPS comes up.
8. **The agent installs the VPS** with nixos-anywhere: the provider's OS is
   replaced by NixOS over SSH, using the identity prepared in step 5.
9. **Done.** Your machine connects to the VPS and the sync starts. The VPS private
   keys are deleted from your machine; nothing secret is ever stored in the repo.

---

## Flow 2: Adding a machine

You do this every time you add a new PC. Two machines take part: the **new
machine** and one **trusted machine** (any machine already in your network).

### On the new machine

1. **Install NixOS** (any basic install) and clone your repo. It's private, so log
   in to GitHub first.
2. **Start your agent** and tell it: *"Join this machine to my nixod network."*
3. **The agent describes the machine** the same way as in Flow 1: NixOS hardware
   configuration first, then drivers and laptop features, folders to sync, and
   anything specific to it.
4. **The agent creates the machine's identity** (Syncthing ID and SSH key) and adds
   it to `network.nix`.
5. **The agent opens a pull request.** This is the **join request**. GitHub
   Actions checks that the new machine and the VPS configs still build.

### On a trusted machine

6. **Ask your agent to review the join request.** It fetches the PR, shows you
   exactly what the new machine adds (its entry, its folders, its config), and
   builds it locally.
7. **Say "approve".** The agent merges the request with a commit **signed by this
   trusted machine** and pushes it.

### Then, on its own

8. **The VPS applies it within minutes.** It fetches the repo, checks the
   signature, and rebuilds. It now accepts the new machine.
9. **You rebuild the new machine.** It connects to the VPS and your folders start
   arriving.
10. **Your other machines catch up on their own** at their next scheduled update.
    Until then they keep syncing through the VPS, so nothing is missing.

---

## Flow 3: Everyday use

- **Change your config** (a new package, a tweak to your shell) on any machine:
  edit, commit (signed), push. Every machine applies it at its next update.
- **Add a synced folder:** list it in `network.nix` for the machines that should
  have it, then commit. Every machine picks it up.
- **Update the system** (newer NixOS packages): update the flake on one machine
  and commit. Everyone follows.
- **Remove a machine** (lost, sold, broken): delete its entry from `network.nix`
  on a trusted machine and commit. The VPS stops accepting it, and it can no
  longer approve changes.
- **Reinstall the VPS:** run the install from Flow 1 again. If the VPS identity
  changes, its entry in `network.nix` is updated and every machine follows.

---

## Flow 4: Recovery (every machine lost, only the VPS left)

Your files are safe: the VPS keeps them and keeps running. What you've lost is a
machine that can approve changes. There are two ways back in, and neither
touches the VPS's data.

**With your recovery passphrase** (given to you once, at setup):
1. Install NixOS on a new machine, clone your repo, start your agent and tell it:
   *"Recover my nixod network."*
2. Enter the passphrase. It unlocks the recovery key stored, encrypted, in your
   repo. The new machine adds itself to the network with it.
3. The VPS accepts the new machine. Rebuild it, and your files come back.
4. You get a **new** passphrase. Write it down; the old one no longer works.

**Without the passphrase**, through your VPS provider's web console:
1. Log into your provider's panel, open the VPS console, and log in with the
   console password you set at setup.
2. Tell the VPS to trust your new machine's key for one single change.
3. The new machine joins itself. The VPS applies that one change, then goes back
   to normal.

> Never reinstall the VPS to get back in: reinstalling wipes its disk, and at
> that point it holds the only copy of your files.

---

## How updates are applied

- **The VPS** checks the repo every few minutes and applies verified changes on
  its own.
- **Your machines** check on a schedule and show a desktop notification when a
  verified update is waiting. You apply it with `nixod update` when it suits
  you.

The technical design is in [PLAN.md](PLAN.md).
