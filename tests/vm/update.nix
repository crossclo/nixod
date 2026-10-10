# Updates with the real services. A `github` VM serves the repo over SSH;
# the hub fetches it with its read-only deploy key (nixod-update.service),
# the host checks it from the user's clone (nixod-check user service) and
# gets a notification. The verification cases themselves are in
# tests/update.nix; here: the plumbing, and trust-once from the console vs
# over SSH.
#
# `nixos-rebuild switch` is replaced by a stub that records the commit (a VM
# has no internet to build a system with): everything up to it is real.
{ self, pkgs }:

let
  inherit (pkgs) lib;
  nixod = self.packages.${pkgs.stdenv.hostPlatform.system}.nixod;

  # Test-only keys, made at build time (never in the repo): the hub's
  # identity through the CLI, the host's user key, GitHub's host key.
  keys =
    pkgs.runCommand "nixod-test-update-keys"
      {
        nativeBuildInputs = [
          nixod
          pkgs.openssh
        ];
      }
      ''
        export HOME=$TMPDIR
        mkdir -p $out
        nixod identity hub hub --staging $out/hub >$out/hub.nix
        ssh-keygen -q -t ed25519 -N "" -C alice@tower -f $out/tower
        ssh-keygen -q -t ed25519 -N "" -C github -f $out/github
      '';
  hub = import "${keys}/hub.nix";
  readKey = file: lib.removeSuffix "\n" (builtins.readFile file);

  network = {
    machines = {
      hub = {
        role = "hub";
        address = "hub";
        inherit (hub) syncthingId sshHostKey deployKey;
      };
      tower = {
        role = "host";
        syncthingId = "TOWERAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA";
        userKey = readKey "${keys}/tower.pub";
        folders.docs = "/home/alice/sync/docs";
      };
    };
    folders.docs = { };
  };
  settings = lib.recursiveUpdate (import ../fixture/settings.nix) {
    repo.url = "git@github:nixod.git";
  };

  apply = pkgs.writeShellScript "apply" ''echo "$2" >>/tmp/nixod-applied'';
  notify = pkgs.writeShellScript "notify" ''echo "$*" >>"$HOME/notifications"'';

  githubKnown = {
    hostNames = [ "github" ];
    publicKey = readKey "${keys}/github.pub";
  };

  machine =
    name: extra:
    lib.recursiveUpdate {
      imports = [ self.nixosModules.default ];
      nixod = {
        inherit name network settings;
        inherit (network.machines.${name}) role;
        update.applyCommand = "${apply}";
        update.notifyCommand = "${notify}";
      };
      programs.ssh.knownHosts.github = githubKnown;
      # nixos-rebuild is stubbed; keep the VMs small.
      documentation.enable = false;
      system.stateVersion = "26.05";
    } extra;
in
pkgs.testers.runNixOSTest {
  name = "nixod-update";
  node.pkgsReadOnly = false;

  nodes = {
    github = {
      services.openssh = {
        enable = true;
        hostKeys = [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
      };
      environment.etc."ssh/ssh_host_ed25519_key" = {
        source = "${keys}/github";
        mode = "0600";
      };
      environment.systemPackages = [ pkgs.git ];
      users.users.git = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [
          hub.deployKey # read-only in real life; the hub only fetches
          (readKey "${keys}/tower.pub")
        ];
      };
    };

    # The hub with the identity install-hub would have put there.
    hub = machine "hub" {
      environment.etc."ssh/ssh_host_ed25519_key" = {
        source = "${keys}/hub/etc/ssh/ssh_host_ed25519_key";
        mode = "0600";
      };
    };

    tower = machine "tower" { };
  };

  testScript = ''
    def alice(cmd):
        return f"su - alice -c {repr(cmd)}"

    def push(message, key="tower"):
        # alice edits her work clone and pushes; key: tower | stranger | unsigned
        sign = "" if key == "unsigned" else f"-c user.signingkey=/home/alice/.ssh/{'id_ed25519' if key == 'tower' else 'stranger'} -c gpg.format=ssh"
        tower.succeed(alice(
            f"cd work && echo {message} >>log && git add log && "
            f"git {sign} commit -q {'-S' if sign else ""} -m {message} && git push -q origin HEAD:main"
        ))
        return tower.succeed(alice("git -C work rev-parse HEAD")).strip()

    def hub_update(ok):
        (hub.succeed if ok else hub.fail)("systemctl start nixod-update.service")
        return hub.succeed("cat /var/lib/nixod/status")

    start_all()
    github.wait_for_unit("sshd.service")
    github.succeed("su - git -c 'git init -q --bare -b main nixod.git'")

    # The hub: deploy key from install-hub; tower: alice's key.
    hub.succeed("install -D -m 600 ${keys}/hub/var/lib/nixod/deploy_key /var/lib/nixod/deploy_key")
    tower.succeed(
        "install -d -m 700 -o alice -g users /home/alice/.ssh",
        "install -m 600 -o alice -g users ${keys}/tower /home/alice/.ssh/id_ed25519",
        "install -m 600 -o alice -g users ${keys}/tower /home/alice/.ssh/nixod_ed25519",
        alice("git config --global user.name alice && git config --global user.email alice@example.org"),
        alice("git config --global init.defaultBranch main"),
        alice("git init -q work && git -C work remote add origin git@github:nixod.git"),
    )

    base = push("base")
    tower.succeed(alice("git clone -q git@github:nixod.git nixod"))
    hub.succeed(f"echo {base} > /var/lib/nixod/revision")  # installed from base

    with subtest("timers are set up"):
        hub.succeed("systemctl is-active nixod-update.timer")
        tower.succeed("loginctl enable-linger alice")
        tower.wait_until_succeeds("systemctl --user -M alice@ is-active nixod-check.timer")

    with subtest("the hub fetches with its deploy key and applies a signed update"):
        assert "up to date" in hub_update(ok=True)
        c1 = push("signed-update")
        assert f"applied {c1}" in hub_update(ok=True)
        hub.succeed(f"grep -q {c1} /tmp/nixod-applied")

    with subtest("the host's check notifies, nixod update applies"):
        tower.succeed("systemctl --user -M alice@ start nixod-check.service")
        tower.succeed(alice("grep -q '1 change(s) ready: run nixod update' notifications"))
        tower.succeed(alice("nixod update"))
        tower.succeed(f"grep -q {c1} /tmp/nixod-applied")
        assert tower.succeed(alice("git -C nixod rev-parse HEAD")).strip() == c1

    with subtest("an unsigned update is rejected, the host gets an urgent notification"):
        push("unsigned", key="unsigned")
        assert "is not signed by a trusted machine" in hub_update(ok=False)
        tower.fail("systemctl --user -M alice@ start nixod-check.service")
        tower.succeed(alice("grep -q 'critical -a nixod nixod: update rejected' notifications"))

    with subtest("trust-once is refused over SSH"):
        tower.succeed(alice("ssh-keygen -q -t ed25519 -N ''' -f .ssh/stranger"))
        stranger = tower.succeed(alice("cat .ssh/stranger.pub")).strip()
        out = tower.fail(alice(f"ssh -o BatchMode=yes root@hub nixod trust-once '{stranger}' 2>&1"))
        assert "this is an SSH session" in out, out
        hub.fail("test -e /var/lib/nixod/trust-once")

    with subtest("trust-once from the console accepts exactly one update"):
        hub.succeed(f"nixod trust-once '{stranger}'")
        t1 = push("new-host-joins", key="stranger")
        assert f"applied {t1}" in hub_update(ok=True)
        hub.fail("test -e /var/lib/nixod/trust-once")
        push("second-commit-same-key", key="stranger")
        assert "is not signed by a trusted machine" in hub_update(ok=False)
  '';
}
