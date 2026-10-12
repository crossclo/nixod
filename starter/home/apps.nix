# Everyday desktop apps.
{
  lib,
  pkgs,
  osConfig,
  ...
}:

{
  # Desktop hosts only (nixod.profiles.x11).
  config = lib.mkIf osConfig.nixod.profiles.x11.enable {
    home.packages = with pkgs; [
      mpv # video player
      imv # image viewer
      pavucontrol # audio mixer
      keepassxc # password manager
    ];

    programs.firefox.enable = true;
  };
}
