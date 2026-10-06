# Framework checks (run by `nix flake check`).
{
  self,
  inputs,
  pkgs,
}:

let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  # Passes when `cond` holds; otherwise fails evaluation with `msg`.
  check =
    name: cond: msg:
    assert lib.assertMsg cond "${name}: ${msg}";
    pkgs.runCommand "nixod-${name}" { } "touch $out";

  # Evaluates a machine without building it: the derivation path is
  # recorded with its context dropped, so nothing gets built.
  evaluates =
    name: machine:
    pkgs.runCommand "nixod-eval-${name}" { } ''
      echo ${builtins.unsafeDiscardStringContext machine.config.system.build.toplevel.drvPath} > $out
    '';

  fixture = self.lib.mkNetwork {
    inherit inputs;
    root = ./fixture;
  };

  template = self.lib.mkNetwork {
    inherit inputs;
    root = ../template;
  };

  templateSettings = import ../template/settings.nix;

  # Lines like `name = null; # NIXOD:FILL ...` in template/settings.nix.
  fillMarkers = lib.filter (line: builtins.match ".*= null;[[:space:]]*# NIXOD:FILL.*" line != null) (
    lib.splitString "\n" (builtins.readFile ../template/settings.nix)
  );

  missingInTemplate = self.lib.missingSettings templateSettings;

  deriveFailures = import ./derive.nix { inherit lib; };
in
{
  # network.nix in, expected Syncthing/SSH config out.
  derive = check "derive" (deriveFailures == [ ]) ("\n" + lib.concatStringsSep "\n" deriveFailures);

  # Hub + 2 hosts in VMs: files sync through the hub only.
  vm-sync = import ./vm/sync.nix { inherit self pkgs; };

  # The CLI in the sandbox: --dry-run changes nothing, identities are reused.
  cli = import ./cli.nix { inherit self pkgs; };

  # Update verification: every accept and reject case, hub and host side.
  update = import ./update.nix { inherit self pkgs; };

  # Updates with the real services: hub over SSH with its deploy key, host
  # check + notification, trust-once on the console vs over SSH.
  vm-update = import ./vm/update.nix { inherit self pkgs; };

  # The join flow: join, review, approve between two machines; the hub and
  # the new host follow.
  vm-join = import ./vm/join.nix { inherit self pkgs; };

  # install-hub on a blank disk; the hub boots with its staged identity.
  vm-install-hub = import ./vm/install-hub.nix { inherit self inputs pkgs; };

  # A dummy host with every profile on, and a dummy hub.
  eval-host = evaluates "host" fixture.nixosConfigurations.tower;
  eval-hub = evaluates "hub" fixture.nixosConfigurations.hub;
  fixture-settings = fixture.checks.${system}.nixod-settings;

  # Every NIXOD:FILL marker is checked, and every check has a marker.
  template-markers =
    check "template-markers"
      (
        lib.length fillMarkers == lib.length missingInTemplate
        && lib.length missingInTemplate == lib.length (import ../lib/settings.nix { inherit lib; }).required
      )
      "template/settings.nix has ${toString (lib.length fillMarkers)} NIXOD:FILL markers, but ${toString (lib.length missingInTemplate)} settings are reported missing";

  # An unfilled template fails `nix flake check`, even with no machine yet.
  template-unfilled-fails = check "template-unfilled-fails" (
    template.nixosConfigurations == { }
    && !(builtins.tryEval template.checks.${system}.nixod-settings).success
  ) "the template's settings check should fail while settings.nix is unfilled";

  # Missing settings surface as NixOS assertions, with their names.
  unfilled-host-assertions =
    let
      machine = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.default
          {
            nixod.role = "host";
            nixod.settings = templateSettings;
            nixpkgs.hostPlatform = "x86_64-linux";
            system.stateVersion = "25.11";
          }
        ];
      };
      failed = map (a: a.message) (lib.filter (a: !a.assertion) machine.config.assertions);
    in
    check "unfilled-host-assertions" (lib.all (m: lib.elem "${m} (NIXOD:FILL in settings.nix)" failed)
      missingInTemplate
    ) "expected one assertion per missing setting, got: ${lib.concatStringsSep "; " failed}";

  # Overriding one default value keeps the others.
  defaults-override =
    let
      sys = fixture.nixosConfigurations.tower.config;
      home = sys.home-manager.users.alice;
    in
    check "defaults-override" (
      sys.zramSwap.memoryPercent == 25
      && sys.zramSwap.algorithm == "zstd"
      && home.programs.kitty.settings.background_opacity == "1.0"
      && home.programs.kitty.settings.cursor_shape == "beam"
      && home.programs.zsh.shellAliases.ll == "eza -l"
      && home.programs.zsh.shellAliases.ls == "eza --icons"
      && home.nixod.theme.colors.yellow == "d4a017"
      && home.nixod.theme.colors.bg == "faf3e1"
    ) "an instance override replaced more than the one value it set";
}
