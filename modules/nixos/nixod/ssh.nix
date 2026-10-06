# SSH trust, generated from network.nix:
#   - every machine knows the hub's host key;
#   - /etc/nixod/allowed_signers lists the keys that may sign commits;
#   - on the hub, every host key may log in.
{ config, lib, ... }:

let
  cfg = config.nixod;
  derive = import ../../../lib/derive.nix { inherit lib; };

  user = cfg.settings.user.name;
  keys = derive.authorizedKeys cfg.network;
in
{
  config = lib.mkMerge [
    {
      programs.ssh.knownHosts = derive.knownHosts cfg.network;

      environment.etc."nixod/allowed_signers".text = derive.allowedSigners cfg.network;
    }

    (lib.mkIf (cfg.role == "hub") {
      users.users = {
        root.openssh.authorizedKeys.keys = keys;
      }
      // lib.optionalAttrs (user != null) {
        ${user}.openssh.authorizedKeys.keys = keys;
      };
    })
  ];
}
