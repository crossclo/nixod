# Your Home Manager setup, applied on every host: shell, editor, desktop,
# dotfiles. nixod only adds git signing and the SSH agent; everything else
# is here, in files you own. For one host only, use hosts/<name>/home.nix.
#
# At setup, your agent ports your existing dotfiles into this directory, and
# copies ready-made files from nixod for what you don't have
# (`nixod starter` lists them). Import each file below.
{ pkgs, ... }:

{
  imports = [ ];

  # Set once, at the first Home Manager generation. Never change it after.
  home.stateVersion = "26.05";
}
