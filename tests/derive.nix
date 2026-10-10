# Unit tests for lib/derive.nix and the network.nix schema: network in,
# expected config out. Returns a list of failure messages.
{ lib }:

let
  derive = import ../lib/derive.nix { inherit lib; };
  errors = (import ../lib/network.nix { inherit lib; }).errors;

  id = prefix: "${prefix}-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA";
  key = name: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholder${name}";

  network = {
    machines = {
      vps = {
        role = "hub";
        address = "203.0.113.10";
        syncthingId = id "VPSAAAA";
        sshHostKey = "${key "VpsHost"} root@vps";
        deployKey = key "VpsDeploy";
      };
      tower = {
        role = "host";
        syncthingId = id "TOWERAA";
        userKey = "${key "Tower"} alice@tower";
        folders = {
          projects = "/home/alice/sync/projects";
          media = "/mnt/storage/media";
        };
      };
      laptop = {
        role = "host";
        syncthingId = id "LAPTOPA";
        userKey = key "Laptop";
        folders.projects = "/home/alice/projects";
      };
    };
    folders = {
      projects.versioning.type = "simple";
      media = {
        label = "Media";
        hub.ignoreDelete = true;
      };
    };
  };

  cases = {
    tower-syncthing = {
      actual = derive.syncthing network "tower";
      expected = {
        devices = {
          laptop.id = id "LAPTOPA";
          vps = {
            id = id "VPSAAAA";
            addresses = [
              "tcp://203.0.113.10:22000"
              "dynamic"
            ];
          };
        };
        folders = {
          projects = {
            path = "/home/alice/sync/projects";
            devices = [
              "vps"
              "laptop"
            ];
            versioning.type = "simple";
          };
          media = {
            path = "/mnt/storage/media";
            devices = [ "vps" ];
            label = "Media";
          };
        };
      };
    };

    hub-syncthing = {
      actual = derive.syncthing network "vps";
      expected = {
        devices = {
          laptop.id = id "LAPTOPA";
          tower.id = id "TOWERAA";
        };
        folders = {
          media = {
            path = "/var/lib/syncthing/media";
            devices = [ "tower" ];
            label = "Media";
            ignoreDelete = true;
          };
          projects = {
            path = "/var/lib/syncthing/projects";
            devices = [
              "laptop"
              "tower"
            ];
            versioning.type = "simple";
          };
        };
      };
    };

    ipv6-hub-address = {
      actual =
        (derive.syncthing (lib.recursiveUpdate network { machines.vps.address = "2001:db8::1"; }) "laptop")
        .devices.vps.addresses;
      expected = [
        "tcp://[2001:db8::1]:22000"
        "dynamic"
      ];
    };

    # Every level inside the home is created, so ~/sync belongs to the user.
    tower-dirs = {
      actual = derive.folderDirs network "tower" "/home/alice";
      expected = [
        "/mnt/storage/media"
        "/home/alice/sync"
        "/home/alice/sync/projects"
      ];
    };

    hub-dirs = {
      actual = derive.folderDirs network "vps" "/home/alice";
      expected = [
        "/var/lib/syncthing/media"
        "/var/lib/syncthing/projects"
      ];
    };

    authorized-keys = {
      actual = derive.authorizedKeys network;
      expected = [
        (key "Laptop")
        "${key "Tower"} alice@tower"
      ];
    };

    known-hosts = {
      actual = derive.knownHosts network;
      expected.vps = {
        hostNames = [
          "vps"
          "203.0.113.10"
        ];
        publicKey = key "VpsHost";
      };
    };

    allowed-signers = {
      actual = derive.allowedSigners network;
      expected = ''
        laptop namespaces="git" ${key "Laptop"}
        tower namespaces="git" ${key "Tower"}
      '';
    };

    # A removed host's key no longer signs or logs in.
    removed-host = {
      actual =
        let
          removed = network // {
            machines = removeAttrs network.machines [ "laptop" ];
          };
        in
        {
          signers = derive.allowedSigners removed;
          keys = derive.authorizedKeys removed;
        };
      expected = {
        signers = ''
          tower namespaces="git" ${key "Tower"}
        '';
        keys = [ "${key "Tower"} alice@tower" ];
      };
    };

    valid-network = {
      actual = errors network;
      expected = [ ];
    };

    empty-network = {
      actual = errors {
        machines = { };
        folders = { };
      };
      expected = [ ];
    };

    # The same key on two machines (copied ~/.ssh), comments aside.
    shared-user-key = {
      actual = errors {
        machines = {
          hub = {
            role = "hub";
            address = "203.0.113.1";
            syncthingId = id "AAAAAAA";
            sshHostKey = key "A";
            deployKey = key "B";
          };
          tower = {
            role = "host";
            syncthingId = id "CCCCCCC";
            userKey = key "D" + " alice@tower";
          };
          laptop = {
            role = "host";
            syncthingId = id "EEEEEEE";
            userKey = key "D" + " alice@laptop";
          };
        };
        folders = { };
      };
      expected = [
        "userKey ${key "D"} is used by more than one machine: each machine needs its own (nixod identity host), or removing one wouldn't revoke it"
      ];
    };

    invalid-network = {
      actual = errors {
        machines = {
          a = {
            role = "hub";
            address = "203.0.113.1";
            syncthingId = "not-an-id";
            sshHostKey = key "A";
            deployKey = key "A";
          };
          b = {
            role = "hub";
            address = "203.0.113.2";
            syncthingId = id "BBBBBBB";
            sshHostKey = "ssh-rsa AAAA";
            deployKey = key "B";
          };
          c = {
            role = "host";
            syncthingId = id "BBBBBBB";
            folders.docs = "relative/docs";
            colour = "blue";
          };
          "bad_name" = {
            role = "desktop";
          };
        };
        folders = { };
      };
      expected = [
        "machines.a.syncthingId is not a Syncthing device ID"
        "machines.b.sshHostKey is not an ssh-ed25519 public key"
        "machines.bad_name.role must be \"host\" or \"hub\""
        "machines.c.userKey is missing"
        "machines.c.colour is not a field of a host"
        "machines.c.folders.docs: there is no folder \"docs\" in folders"
        "machines.c.folders.docs must be an absolute path"
        "there must be exactly one hub (found 2)"
        "Syncthing ID ${id "BBBBBBB"} is used by more than one machine"
      ];
    };
  };
in
lib.concatLists (
  lib.mapAttrsToList (
    name: c:
    lib.optional (c.actual != c.expected)
      "${name}:\n    expected ${lib.generators.toPretty { } c.expected}\n    got      ${
        lib.generators.toPretty { } c.actual
      }"
  ) cases
)
