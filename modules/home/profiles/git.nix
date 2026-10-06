# Git: identity from settings.nix, commits signed with this machine's SSH
# key (the hub and the other hosts only apply signed commits), and gh as the
# credential helper for HTTPS remotes.
{
  config,
  lib,
  osConfig,
  ...
}:

let
  u = osConfig.nixod.settings.user;
  # Only machines already in network.nix have a key the others trust.
  inNetwork = (osConfig.nixod.network.machines or { }) ? ${osConfig.nixod.name};
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  config = lib.mkIf config.nixod.home.git.enable (
    lib.mkMerge [
      # Identity from settings.nix.
      (defaults {
        programs.git.settings.user = lib.filterAttrs (_: v: v != null) {
          name = u.fullName;
          inherit (u) email;
        };
      })
      (defaults {
        programs.git = {
          enable = true;
          settings = {
            init.defaultBranch = "main";
            pull.rebase = true;
            push.autoSetupRemote = true;
            rerere.enabled = true;
          };
          # To use another identity in one repo:
          #   git config user.email "you@example.org"
        };

        # Colored, readable diffs.
        programs.delta = {
          enable = true;
          enableGitIntegration = true;
        };
      })

      # Signed commits, and `git log --show-signature` against the keys the
      # network trusts. The key is the one `nixod identity host` made.
      (lib.mkIf inNetwork (defaults {
        programs.git.signing = {
          format = "ssh";
          key = "${config.home.homeDirectory}/.ssh/id_ed25519";
          signByDefault = true;
        };
        programs.git.settings.gpg.ssh.allowedSignersFile = "/etc/nixod/allowed_signers";
      }))

      # gh logs git into GitHub over HTTPS (no credential to store by hand).
      (defaults {
        programs.gh = {
          enable = true;
          gitCredentialHelper.enable = true;
        };
      })
    ]
  );
}
