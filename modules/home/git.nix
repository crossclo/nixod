# Git: identity from settings.nix, commits signed with this machine's SSH
# key (the hub and the other hosts only apply signed commits), and gh as the
# credential helper for HTTPS remotes. Always on: nixod's own commits
# (init, join, approve, change) depend on it.
#
# Everything here is a default: setting the same option in home/ wins.
# Git taste (aliases, diff tool, pull.rebase...) is the instance's own.
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
  defaults = import ../../lib/defaults.nix { inherit lib; };
in
{
  config = lib.mkMerge [
    (defaults {
      programs.git = {
        enable = true;
        # Identity from settings.nix. To use another one in one repo:
        #   git config user.email "you@example.org"
        settings.user = lib.filterAttrs (_: v: v != null) {
          name = u.fullName;
          inherit (u) email;
        };
      };
    })

    # Signed commits, and `git log --show-signature` against the keys the
    # network trusts. The key is this machine's own, made by
    # `nixod identity host`.
    (lib.mkIf inNetwork (defaults {
      programs.git.signing = {
        format = "ssh";
        key = "${config.home.homeDirectory}/.ssh/nixod_ed25519";
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
  ];
}
