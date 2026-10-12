# Desktop fonts: JetBrains Mono Nerd Font, Inter, Noto (every script, emoji).
#
# The Nerd Font draws the icons in the bar, the prompt and rofi.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Desktop hosts only (nixod.profiles.x11).
  config = lib.mkIf config.nixod.profiles.x11.enable {
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      inter
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];

    fonts.fontconfig.defaultFonts = {
      sansSerif = [
        "Inter"
        "Noto Sans"
      ];
      serif = [ "Noto Serif" ];
      monospace = [ "JetBrainsMono Nerd Font" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
