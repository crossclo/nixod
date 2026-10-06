# Everyday desktop apps.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  config = lib.mkIf config.nixod.home.apps.enable (
    lib.mkMerge [
      {
        home.packages = with pkgs; [
          mpv # video player
          imv # image viewer
          pavucontrol # audio mixer
          keepassxc # password manager
        ];
      }
      (defaults {
        programs.firefox.enable = true;
      })
    ]
  );
}
