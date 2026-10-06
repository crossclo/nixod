{
  imports = [
    ./settings.nix
    ./core.nix
    ./nixod/hub.nix
    ./profiles/desktop-i3.nix
    ./profiles/audio.nix
    ./profiles/networking.nix
    ./profiles/zram.nix
    ./profiles/security-hardening.nix
  ];
}
