# Audio: PipeWire (replaces PulseAudio and JACK).
{ config, lib, ... }:

let
  defaults = import ../../../lib/defaults.nix { inherit lib; };
in
{
  options.nixod.profiles.audio.enable = lib.mkEnableOption "PipeWire audio";

  config = lib.mkIf config.nixod.profiles.audio.enable (defaults {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true; # real-time priorities for audio

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  });
}
