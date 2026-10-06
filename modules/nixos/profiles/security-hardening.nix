# Firewall, sudo, reasonable hardening for a desktop.
{ config, lib, ... }:

let
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  options.nixod.profiles.security-hardening.enable =
    lib.mkEnableOption "firewall, sudo and kernel hardening";

  config = lib.mkIf config.nixod.profiles.security-hardening.enable (defaults {
    networking.firewall.enable = true;

    security = {
      sudo = {
        execWheelOnly = true; # only wheel may invoke sudo
        wheelNeedsPassword = true;
      };
      polkit.enable = true;
    };

    # No SSH daemon on a workstation unless asked for. (The hub turns it on.)
    services.openssh.enable = lib.mkDefault false;

    # Firmware updates (UEFI, SSD, peripherals).
    services.fwupd.enable = true;

    boot.kernel.sysctl = {
      # Hide kernel addresses in /proc (anti-infoleak).
      "kernel.kptr_restrict" = 2;
      # dmesg for root only.
      "kernel.dmesg_restrict" = 1;
      # Classic symlink/hardlink protections in world-writable directories.
      "fs.protected_symlinks" = 1;
      "fs.protected_hardlinks" = 1;
      # ptrace limited to child processes (gdb on your own process still works).
      "kernel.yama.ptrace_scope" = 1;
    };
  });
}
