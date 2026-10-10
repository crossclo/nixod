# `nixod install-hub` installs a hub on a blank disk, and the installed hub
# runs with the identity `nixod identity hub` staged for it (the IDs already
# in network.nix).
#
# The deployer VM plays the first host; the target VM plays the VPS, with an
# empty second disk. kexec needs an installer image from the internet, so
# the target stays on its own NixOS and installs onto the empty disk
# (`--phases disko,install`); the rest is the real command. Afterwards a new
# VM boots from that disk.
{
  self,
  inputs,
  pkgs,
}:

let
  inherit (pkgs) lib;
  nixod = self.packages.${pkgs.stdenv.hostPlatform.system}.nixod;

  # The hub's identity, made by the CLI at build time (test keys only: they
  # live in the store, never in the repo).
  identity = pkgs.runCommand "nixod-test-hub-identity" { nativeBuildInputs = [ nixod ]; } ''
    export HOME=$TMPDIR
    mkdir -p $out
    nixod identity hub hub --staging $out/staging >$out/public.nix
  '';
  public = import "${identity}/public.nix";

  network = {
    machines = {
      hub = {
        role = "hub";
        address = "target";
        inherit (public) syncthingId sshHostKey deployKey;
      };
      tower = {
        role = "host";
        syncthingId = "TOWERAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA";
        userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderTower";
        folders.docs = "/home/alice/sync/docs";
      };
    };
    folders.docs = { };
  };
  networkFile = pkgs.writeText "network.nix" (lib.generators.toPretty { } network);
  # Same network, but the hub's entry has another Syncthing ID.
  wrongNetworkFile = pkgs.writeText "network.nix" (
    lib.generators.toPretty { } (
      lib.recursiveUpdate network {
        machines.hub.syncthingId = "WRONGAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA";
      }
    )
  );

  hub = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.default
      inputs.disko.nixosModules.disko
      (
        { modulesPath, ... }:
        {
          imports = [
            (modulesPath + "/profiles/qemu-guest.nix")
            # Lets the test driver talk to the installed system.
            (modulesPath + "/testing/test-instrumentation.nix")
          ];
          nixod = {
            name = "hub";
            role = "hub";
            inherit network;
            settings = import ../fixture/settings.nix;
          };
          networking.hostName = "hub";
          nixpkgs.hostPlatform = "x86_64-linux";
          # The fixture hub's layout, on the target's empty disk.
          disko.devices = lib.recursiveUpdate (import ../fixture/hosts/hub/disko.nix).disko.devices {
            disk.main.device = "/dev/vdb";
          };
          boot.loader.grub.enable = true;
          documentation.enable = false;
          system.stateVersion = "26.05";
        }
      )
    ];
  };
  hubSystem = hub.config.system.build.toplevel;
  diskoScript = hub.config.system.build.diskoScript;
  syncthing = "${hub.config.services.syncthing.package}/bin/syncthing";
in
pkgs.testers.runNixOSTest {
  name = "nixod-install-hub";

  nodes = {
    deployer = {
      environment.systemPackages = [ nixod ];
      # nixos-anywhere copies these from this VM's store.
      system.extraDependencies = [
        hubSystem
        diskoScript
      ];
      nix.settings.substituters = lib.mkForce [ ];
      virtualisation.memorySize = 2048;
    };

    target = {
      services.openssh.enable = true;
      virtualisation.memorySize = 2048;
      virtualisation.emptyDiskImages = [ 8192 ];
    };
  };

  testScript = ''
    def boot_disk_of(old, name):
        # From nixos-anywhere's own tests: a VM whose only disk is the one
        # the hub was installed on.
        cmd = [
            "${pkgs.qemu_test}/bin/qemu-kvm", "-cpu", "max", "-m", "1024",
            "-virtfs", "local,path=/nix/store,security_model=none,mount_tag=nix-store",
            "-drive", f"file={old.state_dir}/empty0.qcow2,id=drive1,if=none,index=1,werror=report",
            "-device", "virtio-blk-pci,drive=drive1",
        ]
        machine = create_machine(start_command=" ".join(cmd), name=name)
        driver.machines.append(machine)
        return machine

    start_all()
    target.wait_for_unit("sshd.service")
    deployer.wait_for_unit("multi-user.target")

    # The first host can log into the VPS as root (as with a provider's VPS).
    deployer.succeed("ssh-keygen -q -t ed25519 -N ''' -f /root/.ssh/id_ed25519")
    pub = deployer.succeed("cat /root/.ssh/id_ed25519.pub").strip()
    target.succeed(f"install -d -m 700 /root/.ssh && echo '{pub}' >> /root/.ssh/authorized_keys")

    # The staged identity, copied from the store (read-only modes on purpose:
    # install-hub must fix them).
    deployer.succeed("cp -r ${identity}/staging /tmp/staging && chmod -R u+w /tmp/staging")
    deployer.succeed("install -D ${networkFile} /root/instance/network.nix")
    deployer.succeed("install -D ${wrongNetworkFile} /root/wrong/network.nix")

    install = (
        "nixod install-hub hub root@target --stage install --staging /tmp/staging"
        " --store-paths ${diskoScript} ${hubSystem} --no-deploy-key"
    )
    anywhere = "-- -i /root/.ssh/id_ed25519 --phases disko,install"

    with subtest("--dry-run prints the steps and changes nothing"):
        out = deployer.succeed(f"{install} --flake /root/instance --dry-run 2>&1")
        assert "nixos-anywhere" in out and "WIPES" not in out, out
        deployer.succeed("test -d /tmp/staging")
        target.fail("blkid /dev/vdb")

    with subtest("without --yes and without a terminal, it asks and stops"):
        out = deployer.fail(f"{install} --flake /root/instance {anywhere} </dev/null 2>&1")
        assert "Ask the user" in out, out
        target.fail("blkid /dev/vdb")

    with subtest("a staged identity that is not the one in network.nix is refused"):
        out = deployer.fail(f"{install} --flake /root/wrong --yes {anywhere} 2>&1")
        assert "is not machines.hub.syncthingId" in out, out
        target.fail("blkid /dev/vdb")

    with subtest("install"):
        deployer.succeed(f"{install} --flake /root/instance --yes {anywhere} >&2")
        deployer.fail("test -e /tmp/staging")

    target.shutdown()
    hub = boot_disk_of(target, "hub")
    hub.start()
    hub.wait_for_unit("syncthing.service")
    hub.wait_for_unit("sshd.service")

    with subtest("the installed hub runs with the staged identity"):
        hub.succeed("test $(hostname) = hub")
        device_id = hub.succeed("${syncthing} --home /var/lib/syncthing/.config/syncthing device-id").strip()
        assert device_id == "${public.syncthingId}", device_id
        host_key = hub.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub").strip()
        assert host_key == "${public.sshHostKey}", host_key
        hub.succeed(
            "test $(stat -c %U:%a /var/lib/syncthing) = syncthing:700",
            "test $(stat -c %U:%a /var/lib/syncthing/.config/syncthing/key.pem) = syncthing:600",
            "test $(stat -c %U:%a /etc/ssh/ssh_host_ed25519_key) = root:600",
            "test $(stat -c %U:%a /var/lib/nixod/deploy_key) = root:600",
            "test $(stat -c %a /etc) = 755",
            "test $(stat -c %a /var/lib) = 755",
        )
  '';
}
