{
  # Overrides of single default values (checked by tests/default.nix).
  nixod.theme.colors.yellow = "d4a017";
  programs.kitty.settings.background_opacity = "1.0";
  programs.zsh.shellAliases.ll = "eza -l";

  home.stateVersion = "26.05";
}
