{ lib, ... }:

{
  options.nixod.theme.colors = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    description = "UI palette, hex values without \"#\". Each color can be overridden on its own.";
  };

  # Defined per color (not as the option default) so that overriding one
  # color keeps the others.
  config.nixod.theme.colors = lib.mapAttrs (_: lib.mkDefault) (import ./colors.nix);
}
