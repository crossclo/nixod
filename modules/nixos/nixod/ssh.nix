# SSH trust, generated from network.nix:
#   - every machine knows the hub's host key;
#   - /etc/nixod/allowed_signers lists the keys that may sign commits;
#   - on the hub, every host key may log in;
#   - on hosts, `ssh <hub>` uses this machine's nixod key.
{ config, lib, ... }:

let
  cfg = config.nixod;
  derive = import ../../../lib/derive.nix { inherit lib; };

  user = cfg.settings.user.name;
  keys = derive.authorizedKeys cfg.network;
  hub = derive.hub cfg.network;
in
{
  config = lib.mkMerge [
    {
      programs.ssh.knownHosts = derive.knownHosts cfg.network;

      environment.etc."nixod/allowed_signers".text = derive.allowedSigners cfg.network;
    }

    (lib.mkIf (cfg.role == "host" && hub != null) {
      programs.ssh.extraConfig = ''
        # nixod: log into the hub with this machine's key (nixod identity host).
        Host ${
          lib.concatStringsSep " " (
            lib.unique [
              hub.name
              hub.address
            ]
          )
        }
          HostName ${hub.address}
          IdentityFile ~/.ssh/nixod_ed25519
      '';
    })

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
