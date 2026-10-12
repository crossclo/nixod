# Hub + 2 hosts: a file written on host a shows up on host b, while a and b
# never connect to each other directly. Everything goes through the hub.
{ self, pkgs }:

let
  inherit (pkgs) lib;

  # Throwaway Syncthing identities, generated at build time (never stored
  # in the repo). The device ID is read back from the build output.
  identity =
    name:
    pkgs.runCommand "nixod-test-syncthing-${name}" { nativeBuildInputs = [ pkgs.syncthing ]; } ''
      export HOME=$TMPDIR
      syncthing generate --home=$out > log 2>&1
      grep -oE '([A-Z2-7]{7}-){7}[A-Z2-7]{7}' log | head -1 | tr -d '\n' > $out/id
      test -s $out/id
    '';
  idOf = name: builtins.readFile "${identity name}/id";

  key = name: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholder${name}";

  network = {
    machines = {
      hub = {
        role = "hub";
        address = "hub"; # resolved through the test network's /etc/hosts
        syncthingId = idOf "hub";
        sshHostKey = key "HubHost";
        deployKey = key "HubDeploy";
      };
      a = {
        role = "host";
        syncthingId = idOf "a";
        userKey = key "A";
        folders = {
          photos = "/home/alice/sync/photos";
          notes = "/home/alice/sync/notes";
        };
      };
      b = {
        role = "host";
        syncthingId = idOf "b";
        userKey = key "B";
        folders.photos = "/home/alice/photos";
      };
    };
    folders = {
      photos = { };
      notes = { };
    };
  };

  settings = import ../fixture/settings.nix;

in
pkgs.testers.runNixOSTest {
  name = "nixod-sync";

  # core.nix sets nixpkgs.config (allowUnfree), which the test driver's
  # shared pkgs would otherwise refuse.
  node.pkgsReadOnly = false;

  nodes = lib.mapAttrs (
    name: machine:
    { ... }:
    {
      imports = [ self.nixosModules.default ];

      nixod = {
        inherit name network settings;
        inherit (machine) role;
      };

      services.syncthing = {
        cert = "${identity name}/cert.pem";
        key = "${identity name}/key.pem";
        # No discovery: a host can only find the hub (static address).
        settings.options = {
          localAnnounceEnabled = false;
          globalAnnounceEnabled = false;
          relaysEnabled = false;
        };
      };

      # On hosts, Syncthing traffic (port 22000, either end, TCP and UDP,
      # IPv4 and IPv6) is only allowed with the hub, from boot on. Until its
      # settings are applied, Syncthing's LAN discovery also offers IPv6
      # link-local addresses, so this filters on the port, not on addresses.
      networking.firewall.extraCommands = lib.optionalString (machine.role == "host") (
        lib.concatMapStrings
          (rule: ''
            iptables ${rule}
            ip6tables ${rule}
          '')
          [
            "-I INPUT -p tcp -m multiport --ports 22000 ! -s hub -j DROP"
            "-I INPUT -p udp -m multiport --ports 22000 ! -s hub -j DROP"
            "-I OUTPUT -p tcp -m multiport --ports 22000 ! -d hub -j DROP"
            "-I OUTPUT -p udp -m multiport --ports 22000 ! -d hub -j DROP"
          ]
      );

      system.stateVersion = "26.05";
    }
  ) network.machines;

  testScript = ''
    import json

    def api(machine, config_dir, path):
        key = machine.succeed(
            f"grep -oP '(?<=<apikey>)[^<]+' {config_dir}/config.xml"
        ).strip()
        return json.loads(machine.succeed(
            f"curl -sf -H 'X-API-Key: {key}' http://127.0.0.1:8384{path}"
        ))

    start_all()
    for m in [hub, a, b]:
        m.wait_for_unit("syncthing.service")
        m.wait_for_open_port(8384)

    with subtest("folders exist and belong to the user"):
        a.succeed("test \"$(stat -c %U /home/alice/sync)\" = alice")
        a.succeed("test \"$(stat -c %U /home/alice/sync/photos)\" = alice")
        b.succeed("test \"$(stat -c %U /home/alice/photos)\" = alice")

    with subtest("a file written on a reaches b through the hub"):
        a.succeed("su alice -c 'echo hello-from-a > /home/alice/sync/photos/hello.txt'")
        hub.wait_until_succeeds("grep -q hello-from-a /var/lib/syncthing/photos/hello.txt", timeout=300)
        b.wait_until_succeeds("grep -q hello-from-a /home/alice/photos/hello.txt", timeout=300)

    with subtest("a folder only a has reaches the hub, not b"):
        a.succeed("su alice -c 'echo only-a > /home/alice/sync/notes/p.txt'")
        hub.wait_until_succeeds("grep -q only-a /var/lib/syncthing/notes/p.txt", timeout=300)
        b.fail("test -e /home/alice/sync/notes")

    with subtest("a and b never connected directly"):
        # lastSeen stays at the epoch for a device never connected to.
        for m, other in [(a, "${idOf "b"}"), (b, "${idOf "a"}")]:
            stats = api(m, "/home/alice/.config/syncthing", "/rest/stats/device")
            assert stats[other]["lastSeen"].startswith("1970-"), f"{m.name} saw {other}: {stats[other]}"
            assert not stats["${idOf "hub"}"]["lastSeen"].startswith("1970-"), f"{m.name} never saw the hub"
  '';
}
