# Every starter file, imported from the framework's starter/ (an instance
# has copies), so they are all evaluated. dev.nix is imported by one host
# (hosts/tower/home.nix).
let
  starter = ../../../starter/home;
in
{
  imports = map (f: starter + "/${f}.nix") [
    "shell"
    "git"
    "neovim"
    "terminal"
    "i3"
    "rofi"
    "notifications"
    "gtk"
    "apps"
  ];

  # Override of a single value nixod sets (checked by tests/default.nix).
  programs.git.settings.user.email = "alice@work.example";

  home.stateVersion = "26.05";
}
