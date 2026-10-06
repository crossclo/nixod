# Builds a nixod instance (settings.nix + network.nix + hosts/ + home/)
# into nixosConfigurations.
{ self, lib }:

let
  settingsLib = import ./settings.nix { inherit lib; };
  networkLib = import ./network.nix { inherit lib; };

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
in
{
  inherit (settingsLib) missingSettings;

  defaults = import ./defaults.nix { inherit lib; };
  derive = import ./derive.nix { inherit lib; };
  networkErrors = networkLib.errors;

  # inputs:  the instance flake's inputs (nixpkgs, home-manager, disko)
  # root:    the instance repo
  # modules: extra NixOS modules added to every machine (overlays, ...)
  mkNetwork =
    {
      inputs,
      root,
      modules ? [ ],
    }:
    let
      settings = import (root + "/settings.nix");
      missing = settingsLib.missingSettings settings;

      # Every machine is built from a valid network.nix, or not at all.
      networkFile = import (root + "/network.nix");
      networkErrors = networkLib.errors networkFile;
      network = if networkErrors == [ ] then networkFile else throw (networkLib.message networkErrors);

      mkMachine =
        name: machine:
        let
          hostDir = root + "/hosts/${name}";

          # Files every machine of a role must have, with how to make them.
          require =
            file: hint:
            if builtins.pathExists (hostDir + "/${file}") then
              hostDir + "/${file}"
            else
              throw "nixod: hosts/${name}/${file} is missing. ${hint}";

          optionalFile = path: lib.optional (builtins.pathExists path) path;

          inherit (machine) role;

          common = [
            self.nixosModules.default
            {
              nixod = {
                inherit
                  name
                  settings
                  role
                  network
                  ;
              };
              networking.hostName = lib.mkDefault name;
            }
            (require "default.nix" "Describe the machine there (profiles, boot loader, stateVersion).")
            (require "hardware-configuration.nix" (
              if role == "hub" then
                "It is generated during the hub install (nixos-anywhere, --no-filesystems)."
              else
                "Generate it on the machine itself: nixos-generate-config --show-hardware-config > hosts/${name}/hardware-configuration.nix"
            ))
          ];

          host = [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-bak";
                extraSpecialArgs = { inherit inputs; };
                # Left empty until settings.user.name is filled, so the
                # settings assertions are what the user sees.
                users = lib.optionalAttrs (settings.user.name or null != null) {
                  ${settings.user.name}.imports = [
                    self.homeModules.default
                  ]
                  ++ optionalFile (root + "/home/default.nix")
                  ++ optionalFile (hostDir + "/home.nix");
                };
              };
            }
          ];

          hub = [
            inputs.disko.nixosModules.disko
            (require "disko.nix" "Write the hub's disk layout there (see nixod probe).")
          ];
        in
        inputs.nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = common ++ (if role == "hub" then hub else host) ++ modules;
        };
    in
    {
      nixosConfigurations = lib.mapAttrs mkMachine (network.machines or { });

      # `nix flake check` evaluates every machine, which runs the settings
      # assertions. These checks make it fail too when there is no machine yet.
      checks = lib.genAttrs systems (
        system:
        let
          ok = name: inputs.nixpkgs.legacyPackages.${system}.runCommand name { } "touch $out";
        in
        {
          nixod-settings =
            if missing == [ ] then ok "nixod-settings" else throw (settingsLib.missingMessage missing);
          nixod-network = builtins.seq network (ok "nixod-network");
        }
      );
    };
}
