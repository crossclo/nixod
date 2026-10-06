# Updates. The hub applies verified commits on its own (nixod-update.timer);
# hosts check hourly and notify (nixod-check user timer), and the user runs
# `nixod update`. Both verify with /etc/nixod/allowed_signers (ssh.nix).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nixod;
  s = cfg.settings;
  nixod = pkgs.callPackage ../../../pkgs/nixod { };
  inNetwork = (cfg.network.machines or { }) ? ${cfg.name};

  # GitHub's published SSH host key: the hub's deploy key never trusts on
  # first use.
  githubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  hostPath = [
    nixod
    pkgs.git
    pkgs.openssh
    pkgs.libnotify
  ];
in
{
  options.nixod.update = {
    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Hub: time between two checks of the repo.";
    };

    applyCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = ''
        Tests only: runs instead of `nixos-rebuild switch`, with the clone
        and the commit as arguments (a VM test has no internet to build with).
      '';
    };

    notifyCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      internal = true;
      description = "Tests only: runs instead of notify-send.";
    };
  };

  config = lib.mkIf inNetwork (
    lib.mkMerge [
      {
        # What `nixod` needs to know about this machine.
        environment.etc."nixod/config".text = ''
          NIXOD_NAME=${cfg.name}
          NIXOD_ROLE=${cfg.role}
          NIXOD_REPO_URL=${toString s.repo.url}
          NIXOD_BRANCH=${s.repo.branch}
          NIXOD_REPO_PATH=${s.repo.path}
        ''
        + lib.optionalString (cfg.update.applyCommand != null) ''
          NIXOD_APPLY=${cfg.update.applyCommand}
        ''
        + lib.optionalString (cfg.update.notifyCommand != null) ''
          NIXOD_NOTIFY=${cfg.update.notifyCommand}
        '';
      }

      (lib.mkIf (cfg.role == "hub") {
        systemd.services.nixod-update = {
          description = "nixod: apply verified updates";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          # It runs nixos-rebuild switch itself: don't restart it mid-switch.
          restartIfChanged = false;
          stopIfChanged = false;
          path = [
            nixod
            pkgs.git
            pkgs.openssh
            config.nix.package
            config.system.build.nixos-rebuild
          ];
          # Fetch with the read-only deploy key `nixod install-hub` put there.
          environment.GIT_SSH_COMMAND = "ssh -i /var/lib/nixod/deploy_key -o IdentitiesOnly=yes";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${nixod}/bin/nixod update-hub";
          };
        };

        systemd.timers.nixod-update = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitActiveSec = cfg.update.interval;
          };
        };

        systemd.tmpfiles.rules = [ "d /var/lib/nixod 0700 root root -" ];

        programs.ssh.knownHosts."github.com".publicKey = githubKey;
      })

      (lib.mkIf (cfg.role == "host") {
        systemd.user.services.nixod-check = {
          description = "nixod: check for verified updates";
          path = hostPath;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${nixod}/bin/nixod check";
          };
        };

        # 5 minutes after login, then hourly.
        systemd.user.timers.nixod-check = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnStartupSec = "5min";
            OnUnitActiveSec = "1h";
          };
        };
      })
    ]
  );
}
