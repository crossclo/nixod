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
    users.users = lib.optionalAttrs (s.user.name != null) {
      ${s.user.name}.hashedPassword = s.hub.hashedPassword;
    };

    nixod.profiles.zram.enable = lib.mkDefault true;
  };
}
