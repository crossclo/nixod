# nixod: Nix One Desktop

**The same system, the same files, on every machine you own.**

nixod is a NixOS template that gives every machine you own the same configuration
and the same synced folders. A VPS that is always on keeps them in sync. You don't
fill in the template by hand: your AI agent reads `AGENTS.md`, looks at your
hardware and your existing config, and writes your setup for you. All you do is
answer a few questions and rebuild.

> **Status: test phase.** Everything described here is built and passes its
> tests in virtual machines, but it has not run on real machines yet. Don't use
> it on machines or a VPS whose data you can't afford to lose.

---

## The idea

- **One repo describes everything.** Every machine is in it: its system, its
  desktop, its dotfiles, its synced folders, even the VPS disk layout. Nothing is
  configured by hand. If a machine dies, you rebuild it from the repo.
- **Your files follow you.** Folders like `notes`, `photos` or `music` are synced
  between all your machines with Syncthing. The VPS is always online, so two
  machines that are never on at the same time still stay in sync.
- **The network is closed.** A machine only joins if a machine you already trust
  approves it. The repo holds the list of approved machines.
- **Your agent does the setup.** The template contains no personal data. Your agent
  fills it in: your user, your keys, your hardware, your existing dotfiles.
- **Your config is yours.** Your shell, editor and desktop live in your repo
  as plain files you open and edit: your own dotfiles, or ready-made ones
  copied from nixod's starter (an i3 desktop, zsh, Neovim, kitty...). nixod
  itself only carries the wiring: sync, keys, signing, updates. Its fixes
  reach every machine; it never touches your files.

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

Each machine signs with its own key, made for nixod and never shared: removing a
machine from the list revokes it. A machine that was off for a while follows the
list as it changed in between: it accepts changes from machines that joined
since, and refuses those from machines removed since.

A signed change vouches for everything under it, including a join request's
unsigned commits. So **the review is what protects you**: whatever a trusted
machine approves, every machine applies. nixod refuses to sign on top of
commits no trusted machine signed (someone else's push to GitHub): your agent
shows them to you first, and you decide. `nixod review` shows what a join
request adds, the folders the new machine gets, and flags anything else it
changes; read it before saying "approve".

If setup stops halfway (a crash, a logout), tell your agent to resume:
`nixod init-status` shows which steps are done and where to continue.

---

## Flow 1: Setting up your network

You do this once, from your first machine. That machine must already run NixOS.

**You need:** a machine running NixOS, a fresh VPS from any provider (root SSH
access to its stock Linux), and a GitHub account.

1. **Create your repo**, private, from nixod's template (on your first machine;
   `gh auth login` first, HTTPS):

   ```sh
   mkdir ~/nixod && cd ~/nixod && git init -b main
   nix --extra-experimental-features "nix-command flakes" flake init -t github:crossclo/nixod
   git add -A && git commit -m "nixod template"
   gh repo create nixod-config --private --source . --push
   ```

   (Not GitHub's "Use this template" button on nixod: it copies the
   framework, not the template.)
2. **Start your agent** in the repo and tell it: *"This is the setup of my nixod
   network."* It reads `AGENTS.md` and follows the setup steps.
3. **The agent describes your first machine:**
   - generates the machine's **NixOS hardware configuration** (required, always
     the first step),
   - looks at the hardware to pick the right options: graphics card driver
     (NVIDIA), laptop features (battery, touchpad), dual boot, extra disks,
   - reads your current NixOS config and your existing dotfiles (on the machine
     or in your GitHub repos) and brings them into the repo; for what you
     don't have, it offers nixod's starter files (an i3 desktop, zsh, Neovim,
     kitty...), copied into the repo as your own,
   - asks you the basics: user name, time zone, keyboard, which folders to sync.
4. **The agent creates the identities in advance,** for both your machine and the
   VPS: the Syncthing IDs and the SSH keys. Both machines go into `network.nix`
   already knowing each other, so you don't have to come back and fix anything.
   You type the VPS's console password yourself, in a terminal; only its hash
   goes to the VPS, never to the repo.
5. **The agent looks at the VPS before wiping it.** You let your machine's key
   log into it once; the agent then reads the provider's stock system: network
   settings, disk, how it boots. It starts the NixOS installer in the VPS's
   memory, without touching the disk yet, to generate the VPS's hardware
   configuration.
6. **The agent commits** the setup, signed with your machine's key.
7. **The agent installs the VPS** with nixos-anywhere: the provider's OS is
   replaced by NixOS over SSH, using the identity prepared in step 4.
8. **You switch your first machine and reboot.** Your desktop, dotfiles and
   folders are now in place, and the sync starts.
9. **Done.** The VPS private keys are deleted from your machine; nothing secret
   is stored in the repo. Your machine's key has no passphrase at first (the
   agent signs with it); add one if you like, and unlock it once per session.
   With a passphrase, you can also have a dialog ask you each time the key
   is used: then nothing gets signed, by the agent or anything else, without
   your click.

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
   Actions checks that every machine's config still evaluates (the full build
   happens on the trusted machine, at the review).

### On a trusted machine

6. **Ask your agent to review the join request.** It fetches the PR, shows you
   exactly what the new machine adds (its entry, its folders, its config), and
   builds it locally.
7. **Say "approve".** The agent merges the request with a commit **signed by this
   trusted machine** and pushes it.

### Then, on its own

8. **The VPS applies it within minutes.** It fetches the repo, checks the
   signature, and rebuilds. It now accepts the new machine.
9. **You switch the new machine and reboot.** It connects to the VPS and your
   folders start arriving.
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
- **Move to a new VPS** (an empty one: a new provider, a bigger plan): the hub
  steps of Flow 1 again (probe, a new hub identity, its entry in `network.nix`,
  install). The old VPS keeps the files until the new one has synced them.
  Never reinstall a VPS that holds data in place.
- **Reinstall one of your machines** (new disk, fresh NixOS): remove it from
  another machine, then join it again, under the same name if you like.

---

## Flow 4: Recovery (every machine lost, only the VPS left)

Your files are safe: the VPS keeps them and keeps running. What you've lost is a
machine that can approve changes. The way back in goes through your VPS
provider's web console, and doesn't touch the VPS's data:

1. Install NixOS on a new machine, clone your repo, start your agent and tell it:
   *"Recover my nixod network."*
2. Log into your provider's panel, open the VPS console, and log in with the
   console password you set at setup. You read the agent which commit the VPS
   runs, so it can check nobody changed the repo in the meantime.
3. The agent describes the new machine, creates its identity, and pushes the
   commit that adds it to the network.
4. On the console, you tell the VPS to trust that commit's key once, after
   comparing its fingerprint with the one your agent shows. The VPS applies
   that one change, then goes back to normal. Rebuild the new machine, and your
   files come back.

So keep access to your VPS provider account and the console password: with every
machine lost, they are the only way back in.

> **Not implemented, on purpose: a recovery passphrase.** A recovery key,
> encrypted with a generated passphrase and stored in the repo, would let you
> recover without the provider console. It is left out for safety: anyone who
> ever gets a copy of the repo could keep the encrypted key and try to break it
> later ("store now, decrypt later"), with better hardware or a weakness found
> in the encryption. The console needs nothing stored anywhere.

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
