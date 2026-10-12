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

  # The playbooks and AGENTS.md only mention commands, flags and playbooks
  # that exist.
  docs = import ./docs.nix { inherit self pkgs; };

  # An instance exposes the CLI of its pinned framework (`nix run .#nixod`).
  template-nixod = check "template-nixod" (lib.isDerivation
    template.packages.${system}.nixod
  ) "the template's flake has no packages.nixod";

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

  # A dummy host with every profile and every starter file on, and a dummy
  # hub.
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

  # The template ignores `nix build`'s result links: a committed one makes
  # the tree dirty at every build.
  template-gitignore = check "template-gitignore" (
    let
      lines = lib.splitString "\n" (builtins.readFile ../template/.gitignore);
    in
    lib.elem "result" lines && lib.elem "result-*" lines
  ) "template/.gitignore must ignore result and result-*";

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
            system.stateVersion = "26.05";
          }
        ];
      };
      failed = map (a: a.message) (lib.filter (a: !a.assertion) machine.config.assertions);
    in
    check "unfilled-host-assertions" (lib.all (m: lib.elem "${m} (NIXOD:FILL in settings.nix)" failed)
      missingInTemplate
    ) "expected one assertion per missing setting, got: ${lib.concatStringsSep "; " failed}";

  # nixod.home.ssh.confirm: keys added with confirmation, an askpass for the
  # agent, which starts with the graphical session.
  ssh-confirm =
    let
      home =
        (fixture.nixosConfigurations.tower.extendModules {
          modules = [ { home-manager.users.alice.nixod.home.ssh.confirm = true; } ];
        }).config.home-manager.users.alice;
      agent = home.systemd.user.services.ssh-agent;
    in
    check "ssh-confirm" (
      home.programs.ssh.settings."*".data.AddKeysToAgent == "confirm"
      && lib.any (lib.hasPrefix "SSH_ASKPASS=") agent.Service.Environment
      && agent.Install.WantedBy == [ "graphical-session.target" ]
    ) "nixod.home.ssh.confirm doesn't set the agent up for confirmations";

  # Overriding one value nixod sets keeps the others.
  defaults-override =
    let
      sys = fixture.nixosConfigurations.tower.config;
      home = sys.home-manager.users.alice;
    in
    check "defaults-override" (
      sys.zramSwap.memoryPercent == 25
      && sys.zramSwap.algorithm == "zstd"
      && home.programs.git.settings.user.email == "alice@work.example"
      && home.programs.git.settings.user.name == "Alice Example"
    ) "an instance override replaced more than the one value it set";

  # The options of the old built-in profiles fail with what to do instead.
  removed-options =
    let
      fails =
        module:
        !(builtins.tryEval
          (fixture.nixosConfigurations.tower.extendModules { modules = [ module ]; })
          .config.system.build.toplevel.drvPath
        ).success;
    in
    check "removed-options" (
      fails { nixod.profiles.desktop-i3.enable = true; }
      && fails { home-manager.users.alice.nixod.home.neovim.enable = false; }
      && fails { home-manager.users.alice.nixod.theme.colors.bg = "ffffff"; }
    ) "setting a removed profile option should fail";

  # The starter's Neovim config starts without an error, a file of a
  # language with a parser open (the treesitter setup runs). Home Manager's
  # nvim files (init.lua, the plugin pack) are laid out as in a real home.
  starter-neovim =
    let
      home = fixture.nixosConfigurations.tower.config.home-manager.users.alice;
      nvimFiles =
        dir: files:
        lib.concatStrings (
          lib.mapAttrsToList (name: f: ''
            mkdir -p "$(dirname "${dir}/${name}")"
            ln -s ${f.source} "${dir}/${name}"
          '') (lib.filterAttrs (name: _: lib.hasPrefix "nvim/" name) files)
        );
    in
    pkgs.runCommand "nixod-starter-neovim"
      {
        nativeBuildInputs = [
          home.programs.neovim.finalPackage
          pkgs.git # every host has it (core.nix); gitsigns wants it
        ];
      }
      ''
        export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config XDG_DATA_HOME=$TMPDIR/data XDG_STATE_HOME=$TMPDIR/state
        ${nvimFiles "$XDG_CONFIG_HOME" home.xdg.configFile}
        ${nvimFiles "$XDG_DATA_HOME" home.xdg.dataFile}
        echo '{ a = 1; }' >test.nix
        nvim --headless test.nix +qa >out 2>&1 || { cat out; exit 1; }
        if [ -s out ]; then cat out; exit 1; fi
        touch $out
      '';
}
