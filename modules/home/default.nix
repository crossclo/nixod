# What every host's user gets from nixod: the wiring the network relies on,
# nothing else. Git signs commits with this machine's key (the others only
# apply signed commits), and the SSH agent holds that key.
#
# The shell, the editor and the desktop are the instance's own files, in its
# home/: the user's dotfiles, or files copied from nixod's starter/ at init
# (`nixod starter`).
{ lib, ... }:

let
  # Options of the old built-in profiles (before starter/). Setting one fails
  # with a message saying what to do instead.
  removed =
    path:
    lib.mkRemovedOptionModule path ''
      nixod no longer ships a shell, editor or desktop: that config lives in
      your home/ now (`nixod starter` lists ready-made files to copy there).
      Delete this setting.'';
in
{
  imports = [
    ./git.nix
    ./ssh.nix
    (removed [
      "nixod"
      "theme"
    ])
  ]
  ++ map
    (p: removed [
      "nixod"
      "home"
      p
      "enable"
    ])
    [
      "shell"
      "git"
      "neovim"
      "dev"
      "terminal"
      "i3"
      "rofi"
      "notifications"
      "gtk"
      "apps"
    ];

  config.programs.home-manager.enable = true;
}
