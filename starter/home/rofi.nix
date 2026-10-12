# Rofi: app launcher (X11) and the power menu's backend.
# needs: home/colors.nix system/fonts.nix
{
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  c = import ./colors.nix;
in
{
  # Desktop hosts only (nixod.profiles.x11).
  config = lib.mkIf osConfig.nixod.profiles.x11.enable {
    programs.rofi = {
      enable = true;
      package = pkgs.rofi;
      terminal = "${pkgs.kitty}/bin/kitty";
      theme =
        let
          themed = pkgs.writeText "themed.rasi" ''
            * {
                bg:       #${c.bg};
                bg-alt:   #${c.bg-dark};
                bg-hl:    #${c.bg-hl};
                fg:       #${c.fg};
                fg-alt:   #${c.comment};
                accent:   #${c.yellow};

                background-color: transparent;
                text-color: @fg;
                font: "JetBrainsMono Nerd Font 12";
            }

            window {
                background-color: @bg;
                border: 2px;
                border-color: @accent;
                border-radius: 12px;
                width: 620px;
                padding: 16px;
            }

            inputbar {
                children: [ prompt, entry ];
                background-color: @bg-alt;
                border-radius: 8px;
                padding: 10px;
                margin: 0 0 12px 0;
            }

            prompt {
                text-color: @accent;
                margin: 0 8px 0 0;
            }

            entry {
                placeholder: "Search…";
                placeholder-color: @fg-alt;
            }

            listview {
                lines: 8;
                scrollbar: false;
                spacing: 4px;
            }

            element {
                padding: 8px 10px;
                border-radius: 8px;
            }

            element selected {
                background-color: @bg-hl;
                text-color: @accent;
            }

            element-icon {
                size: 22px;
                margin: 0 10px 0 0;
            }
          '';
        in
        "${themed}";
      extraConfig = {
        modi = "drun,run";
        show-icons = true;
        display-drun = "󰀻";
        display-run = "";
        drun-display-format = "{name}";
      };
    };
  };
}
