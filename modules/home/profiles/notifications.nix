# Notifications (dunst): cream background, honey frame. Also where
# `nixod check` update notifications show up.
{ config, lib, ... }:

let
  c = config.nixod.theme.colors;
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  config = lib.mkIf config.nixod.home.notifications.enable (defaults {
    services.dunst = {
      enable = true;
      settings = {
        global = {
          font = "JetBrainsMono Nerd Font 11";
          frame_color = "#${c.yellow}";
          frame_width = 2;
          corner_radius = 10;
          origin = "top-right";
          offset = "16x44";
          width = 380;
          padding = 12;
          horizontal_padding = 14;
          gap_size = 8;
          format = "<b>%s</b>\\n%b";
          markup = "full";
        };
        urgency_low = {
          background = "#${c.bg-dark}";
          foreground = "#${c.fg-dark}";
        };
        urgency_normal = {
          background = "#${c.bg}";
          foreground = "#${c.fg}";
        };
        urgency_critical = {
          background = "#${c.red}";
          foreground = "#${c.bg}";
          frame_color = "#${c.red}";
        };
      };
    };
  });
}
