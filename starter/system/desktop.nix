# The i3 desktop's system half: i3, lock screen, boot splash, GNOME fallback.
#
# home/i3.nix is the rest. i3 itself, the lock screen's PAM entry, a quiet
# boot with a splash, and GNOME (Wayland) as a fallback session in the login
# menu. On top of nixod.profiles.x11, which starts the session (greetd →
# startx → ~/.xsession).
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Desktop hosts only (nixod.profiles.x11).
  config = lib.mkIf config.nixod.profiles.x11.enable {
    # The ~/.xsession entry in the login menu.
    nixod.profiles.x11.sessionName = "i3";

    # -------- Boot splash --------
    boot.plymouth.enable = true;
    boot.consoleLogLevel = 0;
    boot.initrd.verbose = false;
    boot.kernelParams = [
      "quiet"
      "splash"
      "udev.log_priority=3"
      "rd.systemd.show_status=false"
    ];

    # -------- i3 --------
    services.xserver.windowManager.i3 = {
      enable = true;
      package = pkgs.i3;
      extraPackages = with pkgs; [
        feh # wallpaper
      ];
    };

    # PAM entry for i3lock (home/i3.nix uses i3lock-color).
    # Without it, unlocking refuses every password.
    security.pam.services.i3lock = { };

    environment.sessionVariables = {
      _JAVA_AWT_WM_NONREPARENTING = "1"; # Java apps under a tiling WM
    };

    # -------- GNOME fallback (Wayland) --------
    # In the login menu, for when the i3 session is broken. GDM stays off:
    # greetd is the display manager.
    services.desktopManager.gnome.enable = true;
    services.displayManager.gdm.enable = false;
    environment.gnome.excludePackages = with pkgs; [
      epiphany
      geary
      gnome-tour
      gnome-music
      gnome-maps
      gnome-contacts
    ];
  };
}
