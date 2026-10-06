# Compressed swap in RAM (zram): much faster than disk swap, no swap
# partition needed.
{ config, lib, ... }:

let
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  options.nixod.profiles.zram.enable = lib.mkEnableOption "zram swap";

  config = lib.mkIf config.nixod.profiles.zram.enable (defaults {
    zramSwap = {
      enable = true;
      algorithm = "zstd"; # best compression/speed trade-off
      memoryPercent = 50; # max size = 50% of RAM (before compression)
      priority = 100; # used before any disk swap
    };

    # Recommended settings for zram (values from Fedora / Pop!_OS).
    boot.kernel.sysctl = {
      # With swap in RAM, swapping early is a gain, not a cost.
      "vm.swappiness" = 180;
      # Read pages one at a time: there's no seek latency in RAM.
      "vm.page-cluster" = 0;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
    };
  });
}
