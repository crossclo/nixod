{
  description = "My nixod network";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixod = {
      url = "github:crossclo/nixod";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.disko.follows = "disko";
    };
  };

  outputs =
    { nixod, ... }@inputs:
    nixod.lib.mkNetwork {
      inherit inputs;
      root = ./.;
      # Extra NixOS modules for every machine (overlays, ...):
      # modules = [ ];
    };
}
