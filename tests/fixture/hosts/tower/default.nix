# Dummy host: every framework profile on, so they all get evaluated.
# Hardware- and use-specific config (GPU driver, laptop power, Steam,
# Docker...) is written here by the agent, as plain NixOS options.
{
  nixod.profiles = {
    x11 = {
      enable = true;
      autoLogin = true;
    };
    audio.enable = true;
    networking.enable = true;
    zram.enable = true;
    security-hardening.enable = true;
  };

  # Override of a single default value (checked by tests/default.nix).
  zramSwap.memoryPercent = 25;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "26.05";
}
