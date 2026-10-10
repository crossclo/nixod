# Syncthing, generated from network.nix. Hosts run it as the user, with the
# identity `nixod identity host` put in ~/.config/syncthing. The hub runs it
# as the `syncthing` system user, in /var/lib/syncthing.
{ config, lib, ... }:

let
  cfg = config.nixod;
  derive = import ../../../lib/derive.nix { inherit lib; };
  defaults = import ../../../lib/defaults.nix { inherit lib; };

  user = cfg.settings.user.name;
  home = "/home/${toString user}";
  inNetwork = (cfg.network.machines or { }) ? ${cfg.name};
  st = derive.syncthing cfg.network cfg.name;
in
{
  config = lib.mkIf inNetwork (
    lib.mkMerge [
      {
        services.syncthing = {
          enable = true;
          openDefaultPorts = true;
          # network.nix is the only source of devices and folders: anything
          # added in the web UI is dropped at the next start.
          overrideDevices = true;
          overrideFolders = true;
          settings = { inherit (st) devices folders; };
        };
      }

      (defaults {
        services.syncthing.settings.options = {
          # No usage-reporting prompt.
          urAccepted = -1;
          # Hosts reach the hub at its fixed address, and the hub keeps
          # everything, so nothing needs Syncthing's public servers: global
          # discovery would announce every device's IP to them, and relays
          # would carry its traffic. Hosts on the same LAN still find each
          # other (local discovery).
          globalAnnounceEnabled = false;
          relaysEnabled = false;
          localAnnounceEnabled = true;
        };
      })

      (lib.mkIf (cfg.role == "host" && user != null) {
        services.syncthing = {
          inherit user;
          group = "users";
          dataDir = home;
          configDir = "${home}/.config/syncthing";
        };

        # Syncthing needs the folders to exist before it starts.
        systemd.tmpfiles.rules = map (dir: "d ${dir} 0755 ${user} users -") (
          derive.folderDirs cfg.network cfg.name home
        );
      })

      (lib.mkIf (cfg.role == "hub") {
        systemd.tmpfiles.rules = map (dir: "d ${dir} 0700 syncthing syncthing -") (
          derive.folderDirs cfg.network cfg.name home
        );
      })
    ]
  );
}
