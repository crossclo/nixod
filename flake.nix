{
  description = "nixod: the same system and the same files on every machine you own";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Declarative disk layout, used by nixos-anywhere to install the hub.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      nixosModules.default = ./modules/nixos;
      homeModules.default = ./modules/home;

      lib = import ./lib {
        inherit self;
        inherit (nixpkgs) lib;
      };

      templates.default = {
        path = ./template;
        description = "A private nixod instance: your settings, your machines, your dotfiles";
      };

      # x86_64 only: each extra system would evaluate every machine again.
      checks.x86_64-linux = import ./tests {
        inherit self inputs;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
