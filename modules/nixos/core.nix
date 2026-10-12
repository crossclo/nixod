# Foundations shared by every machine: Nix, locale, the user, base tools.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  s = config.nixod.settings;
  defaults = import ../../lib/defaults.nix { inherit lib; };
in
{
  config = lib.mkMerge [
    # Values from settings.nix.
    {
      time.timeZone = s.timeZone;

      i18n.defaultLocale = s.locale;
      i18n.extraLocaleSettings = s.extraLocaleSettings;

      console.keyMap = lib.mkIf (s.keyboard.console != null) s.keyboard.console;

      users.users = lib.optionalAttrs (s.user.name != null) {
        ${s.user.name} = {
          isNormalUser = true;
          description = lib.mkIf (s.user.fullName != null) s.user.fullName;
          extraGroups = [
            "wheel"
            "video"
            "input"
          ]
          ++ lib.optional config.networking.networkmanager.enable "networkmanager";
        };
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # The bare minimum at system level; the rest lives in Home Manager.
      environment.systemPackages = with pkgs; [
        git
        vim
        wget
        curl
        pciutils
        usbutils
        (pkgs.callPackage ../../pkgs/nixod { })
      ];
    }

    (defaults {
      nix = {
        settings.auto-optimise-store = true;
        # Clean up old generations automatically.
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };
      };

      nixpkgs.config.allowUnfree = true;

      # Runs dynamically linked binaries that weren't built by Nix
      # (downloaded tools, vendor binaries, IDE toolboxes...).
      programs.nix-ld.enable = true;

      # man 2/3 (syscalls, libc).
      documentation.dev.enable = true;
    })
  ];
}
