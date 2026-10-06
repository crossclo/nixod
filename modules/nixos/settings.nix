# The instance's settings.nix, as typed options. lib.mkNetwork sets
# `nixod.settings = import ./settings.nix`, so a misspelled key fails
# evaluation instead of being silently ignored.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;

  missing = (import ../../lib/settings.nix { inherit lib; }).missingSettings config.nixod.settings;

  fill =
    description:
    mkOption {
      type = types.nullOr types.str;
      default = null;
      inherit description;
    };
in
{
  options.nixod = {
    role = mkOption {
      type = types.enum [
        "host"
        "hub"
      ];
      description = "This machine's role in network.nix.";
    };

    settings = {
      user = {
        name = fill "Login name.";
        fullName = fill "Full name (user description, git identity).";
        email = fill "Email address (git identity).";
      };

      timeZone = fill "Time zone, e.g. \"Europe/Paris\".";

      locale = mkOption {
        type = types.str;
        default = "en_US.UTF-8";
        description = "Default locale.";
      };

      extraLocaleSettings = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          LC_TIME = "fr_FR.UTF-8";
        };
        description = "Per-category locale overrides (LC_*).";
      };

      keyboard = {
        console = fill "Console keymap, e.g. \"fr\" or \"us\".";
        xkb = fill "X11 keyboard layout, e.g. \"fr\" or \"us\".";
      };

      repo = {
        url = fill "Git URL of the private instance repo.";
        branch = mkOption {
          type = types.str;
          default = "main";
          description = "Branch every machine follows.";
        };
        path = mkOption {
          type = types.str;
          default = "~/nixod";
          description = "Where the clone lives on hosts.";
        };
      };

      hub.hashedPassword = fill ''
        Password hash for the user on the hub (mkpasswd -m sha-512). Only
        used on the provider's console; SSH password login stays disabled.
      '';
    };
  };

  config.assertions = map (message: {
    assertion = false;
    message = "${message} (NIXOD:FILL in settings.nix)";
  }) missing;
}
