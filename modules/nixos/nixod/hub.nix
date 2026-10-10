# Hub role: headless, hardened SSH, console password for recovery.
# SSH keys and Syncthing come from network.nix (ssh.nix, syncthing.nix).
{ config, lib, ... }:

let
  s = config.nixod.settings;
in
{
  config = lib.mkIf (config.nixod.role == "hub") {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    networking.firewall.enable = true;

    # Login on the provider's VNC/serial console, for when SSH is down or
    # during a recovery (`nixod trust-once`). SSH password login stays off.
    # The hash is put on the hub at install (`nixod identity hub
    # --console-password`), never in the repo. Users are mutable: it is read
    # when the user is created; change it later with `passwd` (as root, over
    # SSH).
    users.users = lib.optionalAttrs (s.user.name != null) {
      ${s.user.name}.hashedPasswordFile = "/var/lib/nixod/console-password";
    };

    nixod.profiles.zram.enable = lib.mkDefault true;
  };
}
