# zsh as the login shell (home/shell.nix configures it).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  user = config.nixod.settings.user.name;
in
{
  # Needed at system level for zsh to be a valid login shell.
  programs.zsh.enable = true;

  users.users = lib.optionalAttrs (user != null) {
    ${user}.shell = pkgs.zsh;
  };
}
