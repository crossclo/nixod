# Default user setup. Every profile can be turned off from the instance:
#   nixod.home.dev.enable = true;
#   nixod.home.neovim.enable = false;
# Profiles tied to the desktop follow osConfig.nixod.profiles.desktop-i3.enable.
{ lib, osConfig, ... }:

let
  desktop = osConfig.nixod.profiles.desktop-i3.enable;

  profile =
    default: description:
    lib.mkOption {
      type = lib.types.bool;
      inherit default description;
    };
in
{
  imports = [
    ./theme
    ./profiles/shell.nix
    ./profiles/git.nix
    ./profiles/neovim.nix
    ./profiles/dev.nix
    ./profiles/terminal.nix
    ./profiles/i3.nix
    ./profiles/rofi.nix
    ./profiles/notifications.nix
    ./profiles/gtk.nix
    ./profiles/apps.nix
  ];

  options.nixod.home = {
    shell.enable = profile true "zsh, starship and modern CLI tools";
    git.enable = profile true "git with the identity from settings.nix";
    neovim.enable = profile true "Neovim with LSP, completion and Telescope";
    dev.enable = profile false "compilers, debuggers and dev tools";
    terminal.enable = profile desktop "the kitty terminal";
    i3.enable = profile desktop "the i3 config (bar, lock screen, compositor)";
    rofi.enable = profile desktop "the rofi launcher";
    notifications.enable = profile desktop "dunst notifications";
    gtk.enable = profile desktop "GTK/Qt/cursor theme";
    apps.enable = profile desktop "desktop apps (browser, media, password manager)";
  };

  config.programs.home-manager.enable = true;
}
