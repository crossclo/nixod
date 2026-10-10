# describe-host: write hosts/<name>/ for this machine

Shared by init, join and recover. Run everything **on the machine itself**.
`<name>` is the machine's name in `network.nix` (default: `hostname`).

## 1. Hardware configuration (always first)

```sh
mkdir -p hosts/<name>
nixos-generate-config --show-hardware-config > hosts/<name>/hardware-configuration.nix
```

Never copy it from another machine, never write it by hand. Compare it with
`/etc/nixos/hardware-configuration.nix`: anything added there by hand (mounts,
kernel modules, options) is kept, in `hosts/<name>/default.nix`. Show the user
what you kept.

## 2. Hardware: what this machine needs

Look, then write plain NixOS options in `hosts/<name>/default.nix`. nixod has
no hardware profiles: you write what this machine needs.

- **GPU** (`lspci | grep -iE 'vga|3d'`). NVIDIA:
  ```nix
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    # Turing (GTX 16xx, RTX 20xx) and newer:
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Maxwell, Pascal (GTX 9xx, 10xx) and Volta: the current driver no longer
    # supports them; the 580 branch does:
    #   open = false;
    #   package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };
  ```
  Older cards (Kepler and before): `legacy_470` or older, see the NixOS manual.
  AMD or Intel: nothing to add.
- **Laptop** (`ls /sys/class/power_supply/BAT*`): `services.power-profiles-daemon.enable`,
  `services.upower.enable`, touchpad in `services.libinput.touchpad`, and
  `services.thermald.enable` on Intel only (`grep -m1 vendor_id /proc/cpuinfo`).
  The i3 bar shows the battery by itself.
- **Another OS** (`lsblk -f`, `efibootmgr`): keep the boot loader the machine
  already uses, with its setup from `/etc/nixos/configuration.nix`.
  systemd-boot usually lists Windows by itself when it is on the same EFI
  partition: nothing to add. With GRUB and Windows on another EFI partition,
  a GRUB entry that chainloads it by the partition's UUID is the reliable way
  (os-prober misses it when rebuilding from a chroot).
- **Data disks**: the generated hardware configuration already mounts them.
  Don't edit that file: add `nofail` in `hosts/<name>/default.nix`, so a
  missing disk doesn't block the boot:
  `fileSystems."/mnt/data".options = [ "nofail" ];`
- **Disk encryption** (`lsblk -f`: a `crypto_LUKS` partition): note it. It
  matters for this machine's nixod key, which has no passphrase at first:
  tell the user at the end of init or join.
- **No swap partition**: `nixod.profiles.zram.enable = true;` (plus a
  `swapDevices` swapfile when there is little RAM).

Show the user what you found and what you plan to write; wait for their yes.

## 3. The existing config

From `/etc/nixos/configuration.nix`, bring over what isn't hardware or already
covered by nixod (services, packages, settings). Keep `system.stateVersion`
exactly as it is there.

**Not Syncthing**: an existing `services.syncthing` config (devices, folders)
isn't brought over. nixod generates Syncthing from `network.nix`; old folders
become `network.nix` folders (ask the user which), old devices are dropped.

**Not the old desktop**, when `desktop-i3` is on: leave out its display
manager (`services.displayManager.gdm`, `sddm`, `services.xserver.displayManager.lightdm`)
and its desktop (`services.desktopManager.gnome`, `plasma6`, ...). desktop-i3
starts greetd, and refuses to build next to another display manager. Ask the
user first: if they'd rather keep their old desktop, leave `desktop-i3` off
and bring the old desktop over instead. (GNOME stays available from the
greetd menu by default: `nixod.profiles.desktop-i3.gnomeFallback`.)

nixod's profiles (`nixod.profiles.<name>.enable`): `desktop-i3`, `audio`,
`networking`, `zram`, `security-hardening`. A desktop host usually enables all
of them:

```nix
{ config, pkgs, ... }:
{
  nixod.profiles = {
    desktop-i3.enable = true;
    audio.enable = true;
    networking.enable = true;
    zram.enable = true;
    security-hardening.enable = true;
  };
  # boot loader, hardware options, ...
  system.stateVersion = "<from /etc/nixos/configuration.nix>";
}
```

## 4. Dotfiles

Look locally (`~/.config`, `~/.zshrc`, `~/.gitconfig`, an existing Home Manager
config) and on GitHub (`nix run nixpkgs#gh -- repo list`, repos that look like
dotfiles). An existing Home Manager config: keep its `home.stateVersion` (in
`home/default.nix`, instead of the template's), it changes how some files are
managed. Port
them to Home Manager options where they exist, else `xdg.configFile` /
`home.file`, into `home/` (every host) or `hosts/<name>/home.nix` (this one).
**In a join or a recovery, only `hosts/<name>/home.nix`** (and files under
`hosts/<name>/`): the join request carries only `network.nix` and
`hosts/<name>/`, so a change in `home/` would be missing from it. Shared
changes go in a `change` once the machine is in.

Everything nixod's profiles set is a default: setting the same option in
`home/` wins and keeps the rest. Profiles turn off with
`nixod.home.<profile>.enable = false;` (shell, git, neovim, dev, terminal, i3,
rofi, notifications, gtk, apps). What the user's dotfiles don't cover comes
from nixod's defaults.

## 5. Folders

Ask which folders this machine syncs, and where. They go in the machine's
`network.nix` entry, written right after this (init step 3, join step 2),
together with its identity.
