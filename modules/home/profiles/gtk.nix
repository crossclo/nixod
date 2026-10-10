# GTK/Qt/cursor theme: light everywhere, GNOME fallback session included.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  xkb = osConfig.nixod.settings.keyboard.xkb;
  variant = osConfig.nixod.settings.keyboard.xkbVariant;
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  config = lib.mkIf config.nixod.home.gtk.enable (defaults {
    gtk = {
      enable = true;
      theme = {
        # Light libadwaita backported to GTK3: GTK3 and GTK4 look the same.
        name = "adw-gtk3";
        package = pkgs.adw-gtk3;
      };
      iconTheme = {
        name = "Papirus-Light";
        package = pkgs.papirus-icon-theme;
      };
      gtk3.extraConfig.gtk-application-prefer-dark-theme = 0;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = 0;
    };

    home.pointerCursor = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
      size = 24;
      gtk.enable = true;
    };

    qt = {
      enable = true;
      platformTheme.name = "adwaita";
      style.name = "adwaita";
    };

    # The GNOME fallback session follows the same theme and keyboard.
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-light";
        gtk-theme = "adw-gtk3";
        icon-theme = "Papirus-Light";
      };
    }
    // lib.optionalAttrs (xkb != null) {
      "org/gnome/desktop/input-sources" = {
        sources = [
          (config.lib.gvariant.mkTuple [
            "xkb"
            (xkb + lib.optionalString (variant != "") "+${variant}")
          ])
        ];
      };
    };
  });
}
