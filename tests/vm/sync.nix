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
          docs = "/home/alice/sync/docs";
          projects = "/home/alice/sync/projects";
        };
      };
      b = {
        role = "host";
        syncthingId = idOf "b";
        userKey = key "B";
        folders.docs = "/home/alice/docs";
      };
    };
    folders = {
      docs = { };
      projects = { };
    };
  };

  settings = import ../fixture/settings.nix;

  hosts = lib.attrNames (lib.filterAttrs (_: m: m.role == "host") network.machines);
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

      # Hosts may only reach each other through the hub, from boot on (IPv6
      # too: Syncthing's discovery runs until its settings are applied).
      networking.firewall.extraCommands = lib.concatMapStrings (other: ''
        iptables -I INPUT -s ${other} -j DROP
        iptables -I OUTPUT -d ${other} -j DROP
        ip6tables -I INPUT -s ${other} -j DROP
        ip6tables -I OUTPUT -d ${other} -j DROP
      '') (lib.optionals (machine.role == "host") (lib.remove name hosts));

      system.stateVersion = "25.11";
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
        a.succeed("test \"$(stat -c %U /home/alice/sync/docs)\" = alice")
        b.succeed("test \"$(stat -c %U /home/alice/docs)\" = alice")

    with subtest("a file written on a reaches b through the hub"):
        a.succeed("su alice -c 'echo hello-from-a > /home/alice/sync/docs/hello.txt'")
        hub.wait_until_succeeds("grep -q hello-from-a /var/lib/syncthing/docs/hello.txt", timeout=300)
        b.wait_until_succeeds("grep -q hello-from-a /home/alice/docs/hello.txt", timeout=300)

    with subtest("a folder only a has reaches the hub, not b"):
        a.succeed("su alice -c 'echo only-a > /home/alice/sync/projects/p.txt'")
        hub.wait_until_succeeds("grep -q only-a /var/lib/syncthing/projects/p.txt", timeout=300)
        b.fail("test -e /home/alice/sync/projects")

    with subtest("a and b never connected directly"):
        # lastSeen stays at the epoch for a device never connected to.
        for m, other in [(a, "${idOf "b"}"), (b, "${idOf "a"}")]:
            stats = api(m, "/home/alice/.config/syncthing", "/rest/stats/device")
            assert stats[other]["lastSeen"].startswith("1970-"), f"{m.name} saw {other}: {stats[other]}"
            assert not stats["${idOf "hub"}"]["lastSeen"].startswith("1970-"), f"{m.name} never saw the hub"
  '';
}
