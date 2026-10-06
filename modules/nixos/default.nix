{
  imports = [
    ./settings.nix
    ./core.nix
    ./nixod/network.nix
    ./nixod/hub.nix
    ./nixod/syncthing.nix
    ./nixod/ssh.nix
    ./profiles/desktop-i3.nix
    ./profiles/audio.nix
    ./profiles/networking.nix
    ./profiles/zram.nix
    ./profiles/security-hardening.nix
  ];
}
