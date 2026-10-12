{
  imports = [
    ./settings.nix
    ./core.nix
    ./nixod/network.nix
    ./nixod/hub.nix
    ./nixod/syncthing.nix
    ./nixod/ssh.nix
    ./nixod/update.nix
    ./profiles/x11.nix
    ./profiles/audio.nix
    ./profiles/networking.nix
    ./profiles/zram.nix
    ./profiles/security-hardening.nix
  ];
}
