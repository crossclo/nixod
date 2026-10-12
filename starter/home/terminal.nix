# Kitty: GPU terminal, themed from colors.nix.
# needs: home/colors.nix system/fonts.nix
{ lib, osConfig, ... }:

let
  c = import ./colors.nix;
in
{
  # Desktop hosts only (nixod.profiles.x11).
  config = lib.mkIf osConfig.nixod.profiles.x11.enable {
    programs.kitty = {
      enable = true;
      font = {
        name = "JetBrainsMono Nerd Font";
        size = 12;
      };
      settings = {
        # Look
        background_opacity = "0.95";
        window_padding_width = 10;
        hide_window_decorations = "yes";
        cursor_shape = "beam";
        enable_audio_bell = false;
        confirm_os_window_close = 0;
        scrollback_lines = 10000;

        # Palette
        background = "#${c.bg}";
        foreground = "#${c.fg}";
        selection_background = "#${c.bg-hl}";
        selection_foreground = "#${c.fg}";
        cursor = "#${c.fg}";
        cursor_text_color = "#${c.bg}";
        url_color = "#${c.teal}";
        active_border_color = "#${c.blue}";
        inactive_border_color = "#${c.gray}";
        active_tab_background = "#${c.blue}";
        active_tab_foreground = "#${c.bg-dark}";
        inactive_tab_background = "#${c.bg-hl}";
        inactive_tab_foreground = "#${c.comment}";

        color0 = "#${c.black}";
        color1 = "#${c.red}";
        color2 = "#${c.green}";
        color3 = "#${c.yellow}";
        color4 = "#${c.blue}";
        color5 = "#${c.magenta}";
        color6 = "#${c.cyan}";
        color7 = "#${c.fg-dark}";
        color8 = "#${c.gray}";
        color9 = "#${c.red}";
        color10 = "#${c.green}";
        color11 = "#${c.yellow}";
        color12 = "#${c.blue}";
        color13 = "#${c.magenta}";
        color14 = "#${c.cyan}";
        color15 = "#${c.fg}";
      };
    };
  };
}
