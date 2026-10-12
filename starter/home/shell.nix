# Shell: zsh + starship + modern CLI tools.
# needs: home/colors.nix system/shell.nix
{
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  c = import ./colors.nix;
  repo = osConfig.nixod.settings.repo.path;
  host = osConfig.networking.hostName;
in
{
  home.packages = with pkgs; [
    btop # system monitor
    eza # modern ls
    bat # cat with highlighting
    ripgrep # fast grep (rg)
    fd # fast find
    jq # JSON
    tldr # short man pages
    tree
    unzip
    zip
    p7zip
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 50000;
      ignoreDups = true;
      share = true;
    };

    shellAliases = {
      # NixOS (this machine, from the local clone)
      nrs = "sudo nixos-rebuild switch --flake ${repo}#${host}";
      nrt = "sudo nixos-rebuild test --flake ${repo}#${host}";
      nfu = "nix flake update --flake ${repo}";

      # Quality of life
      ls = "eza --icons";
      ll = "eza -la --icons --git";
      lt = "eza --tree --level=2 --icons";
      cat = "bat --style=plain";
      grep = "rg";
      ".." = "cd ..";
    }
    // lib.optionalAttrs osConfig.virtualisation.docker.enable {
      d = "docker";
      dc = "docker compose";
      ld = "lazydocker";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$nix_shell$cmd_duration$character";

      directory = {
        style = "bold #${c.blue}";
        truncation_length = 3;
      };
      git_branch = {
        symbol = " ";
        style = "bold #${c.magenta}";
      };
      git_status.style = "bold #${c.orange}";
      nix_shell = {
        symbol = "󱄅 ";
        style = "bold #${c.cyan}";
        format = "[$symbol$state]($style) ";
      };
      cmd_duration = {
        min_time = 2000;
        style = "#${c.comment}";
      };
      character = {
        success_symbol = "[❯](bold #${c.green})";
        error_symbol = "[❯](bold #${c.red})";
      };
    };
  };

  # Jump to frequent directories: `z nixod`
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Fuzzy search: Ctrl+R (history), Ctrl+T (files)
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    colors = {
      bg = "#${c.bg}";
      fg = "#${c.fg}";
      hl = "#${c.blue}";
      "bg+" = "#${c.bg-hl}";
      "fg+" = "#${c.fg}";
      "hl+" = "#${c.cyan}";
      pointer = "#${c.magenta}";
      prompt = "#${c.blue}";
    };
  };

  # Per-project dev environments (`.envrc` + `use flake`).
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
