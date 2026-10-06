# Git, with the identity from settings.nix.
{
  config,
  lib,
  osConfig,
  ...
}:

let
  u = osConfig.nixod.settings.user;
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
    ]
  );
}
