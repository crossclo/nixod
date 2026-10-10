# Your personal Home Manager setup, applied on every host after nixod's
# defaults. Imported dotfiles and personal tool sets go here (or in other
# files of this directory, imported below). For one host only, use
# hosts/<name>/home.nix.
#
# Everything nixod's profiles set is a default: set the same option here
# and yours wins, the rest stays. Lists like home.packages add up.
#   nixod.home.dev.enable = true;              # turn a profile on/off
#   nixod.theme.colors.yellow = "e3a51a";      # one theme color
#   programs.kitty.settings.font_size = 13;    # one setting
#   programs.zsh.shellAliases.ll = "ls -l";    # one alias
{ pkgs, ... }:

{
  imports = [ ];

  # Set once, at the first Home Manager generation. Never change it after.
  home.stateVersion = "26.05";
}
