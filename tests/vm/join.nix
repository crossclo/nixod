# The join flow between two machines. laptop (new) sends its join request;
# tower (trusted) reviews and approves it; the hub applies the signed merge;
# laptop updates to it. On the way: approve refuses a request it hasn't
# reviewed or that changed after review, and review flags shared files.
#
# The request is a branch on a `github` VM (no GitHub API: `--no-pr`, and
# review/approve take the branch name). Builds are skipped (`--no-build`)
# and `nixos-rebuild switch` is stubbed: a VM has no internet to build with.
{ self, pkgs }:

let
  inherit (pkgs) lib;
  nixod = self.packages.${pkgs.stdenv.hostPlatform.system}.nixod;

  # Test-only keys, made at build time with the CLI (never in the repo).
  keys =
    pkgs.runCommand "nixod-test-join-keys"
      {
        nativeBuildInputs = [
          nixod
          pkgs.openssh
        ];
      }
      ''
        mkdir -p $out
        HOME=$TMPDIR nixod identity hub hub --staging $out/hub >$out/hub.nix
        HOME=$out/laptop nixod identity host laptop --no-passphrase >$out/laptop.nix
        ssh-keygen -q -t ed25519 -N "" -C alice@tower -f $out/tower
        ssh-keygen -q -t ed25519 -N "" -C github -f $out/github
      '';
  readKey = file: lib.removeSuffix "\n" (builtins.readFile file);
  hub = import "${keys}/hub.nix";
  laptop = import "${keys}/laptop.nix";

  base = {
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
  # What laptop's join request adds.
  joined = lib.recursiveUpdate base {
    machines.laptop = {
      role = "host";
      inherit (laptop) syncthingId userKey;
      folders.docs = "/home/alice/docs";
    };
  };
  nixFile = name: value: pkgs.writeText name (lib.generators.toPretty { } value);
  hostFile = pkgs.writeText "default.nix" "{ }\n";

  settings = lib.recursiveUpdate (import ../fixture/settings.nix) {
    repo.url = "git@github:nixod.git";
  };
  apply = pkgs.writeShellScript "apply" ''echo "$2" >>/tmp/nixod-applied'';

  machine = name: network: {
    imports = [ self.nixosModules.default ];
    nixod = {
      inherit name network settings;
      inherit (network.machines.${name}) role;
      update.applyCommand = "${apply}";
    };
    programs.ssh.knownHosts.github = {
      hostNames = [ "github" ];
      publicKey = readKey "${keys}/github.pub";
    };
    documentation.enable = false;
    system.stateVersion = "25.11";
  };
in
pkgs.testers.runNixOSTest {
  name = "nixod-join";
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
          hub.deployKey
          (readKey "${keys}/tower.pub")
          laptop.userKey
        ];
      };
    };
    # The hub and tower run the network as it is; laptop runs the one its
    # request describes.
    hub = machine "hub" base;
    tower = machine "tower" base;
    laptop = machine "laptop" joined;
  };

  testScript = ''
    import shlex

    def alice(machine, cmd, ok=True):
        run = machine.succeed if ok else machine.fail
        return run(f"su - alice -c {shlex.quote(cmd + ' 2>&1')}")

    start_all()
    github.wait_for_unit("sshd.service")
    github.succeed("su - git -c 'git init -q --bare -b main nixod.git'")
    hub.succeed("install -D -m 600 ${keys}/hub/var/lib/nixod/deploy_key /var/lib/nixod/deploy_key")

    for m in [tower, laptop]:
        m.succeed("install -d -m 700 -o alice -g users /home/alice/.ssh")
        alice(m, "git config --global user.name alice && git config --global user.email alice@example.org"
                 " && git config --global init.defaultBranch main")
    # tower signs its commits (Home Manager's git profile does this on nixod hosts).
    tower.succeed("install -m 600 -o alice -g users ${keys}/tower /home/alice/.ssh/id_ed25519")
    alice(tower, "git config --global gpg.format ssh && git config --global user.signingkey ~/.ssh/id_ed25519")
    # laptop has the identity `nixod identity host laptop` made.
    laptop.succeed(
        "cp -r --no-preserve=mode ${keys}/laptop/.ssh ${keys}/laptop/.config /home/alice/",
        "chown -R alice:users /home/alice/.ssh /home/alice/.config",
        "chmod 600 /home/alice/.ssh/id_ed25519",
    )

    # The network as it is: hub + tower, pushed signed by tower.
    alice(tower, "mkdir -p nixod/hosts/hub nixod/hosts/tower && cd nixod && git init -q"
                 " && cp ${nixFile "network.nix" base} network.nix"
                 " && cp ${hostFile} hosts/hub/default.nix && cp ${hostFile} hosts/tower/default.nix"
                 " && git add . && git commit -q -S -m base"
                 " && git remote add origin git@github:nixod.git && git push -q -u origin main")
    base = alice(tower, "git -C nixod rev-parse HEAD").strip()
    hub.succeed(f"echo {base} > /var/lib/nixod/revision")
    alice(laptop, "git clone -q git@github:nixod.git nixod")

    with subtest("laptop sends its join request"):
        alice(laptop, "cd nixod && mkdir -p hosts/laptop && cp ${nixFile "network.nix" joined} network.nix"
                      " && cp ${hostFile} hosts/laptop/default.nix && cp ${hostFile} hosts/laptop/hardware-configuration.nix"
                      " && nixod join laptop --no-build --no-pr")
        github.succeed("su - git -c 'git -C nixod.git rev-parse --verify join/laptop'")

    with subtest("approve refuses a request it hasn't reviewed"):
        out = alice(tower, "cd nixod && nixod approve join/laptop", ok=False)
        assert "not reviewed" in out, out

    with subtest("review shows the new host"):
        out = alice(tower, "cd nixod && nixod review join/laptop --no-build")
        assert "+ laptop (new)" in out and "shared files" not in out, out

    with subtest("a request changed after review is refused; shared files are flagged"):
        alice(laptop, "cd nixod && mkdir -p home && echo '{ }' > home/default.nix"
                      " && git add home && git commit -q -m 'sneaky' && git push -q")
        out = alice(tower, "cd nixod && nixod approve join/laptop", ok=False)
        assert "changed since the review" in out, out
        out = alice(tower, "cd nixod && nixod review join/laptop --no-build")
        assert "this request also changes shared files" in out and "home/default.nix" in out, out
        alice(laptop, "cd nixod && git rm -q -r home && git commit -q -m 'undo' && git push -q")
        out = alice(tower, "cd nixod && nixod review join/laptop --no-build")
        assert "shared files" not in out, out

    with subtest("approve merges with a commit signed by tower"):
        alice(tower, "cd nixod && nixod approve join/laptop")
        merge = github.succeed("su - git -c 'git -C nixod.git rev-parse main'").strip()
        assert merge == alice(tower, "git -C nixod rev-parse HEAD").strip()
        alice(tower, "git -C nixod -c gpg.ssh.allowedSignersFile=/etc/nixod/allowed_signers verify-commit HEAD")

    with subtest("the hub applies the approved join"):
        hub.succeed("systemctl start nixod-update.service")
        status = hub.succeed("cat /var/lib/nixod/status")
        assert f"applied {merge}" in status, status

    with subtest("laptop updates to the approved commit"):
        alice(laptop, "nixod update")
        assert alice(laptop, "git -C nixod rev-parse --abbrev-ref HEAD").strip() == "main"
        assert alice(laptop, "git -C nixod rev-parse HEAD").strip() == merge
        laptop.succeed(f"grep -q {merge} /tmp/nixod-applied")
  '';
}
