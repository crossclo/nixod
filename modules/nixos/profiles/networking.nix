# Network (NetworkManager), printing, Bluetooth.
{ config, lib, ... }:

let
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  options.nixod.profiles.networking.enable =
    lib.mkEnableOption "NetworkManager, printing and Bluetooth";

  config = lib.mkIf config.nixod.profiles.networking.enable (defaults {
    networking.networkmanager.enable = true;

    # Printing + network printer discovery.
    services.printing.enable = true;
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    services.blueman.enable = true;
  });
}
