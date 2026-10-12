# The SSH agent, which holds this machine's nixod key once it has a
# passphrase (commit signing, logins to the hub), optionally asking for a
# confirmation each time the key is used.
#
# Everything here is a default: another agent (gpg-agent, keychain...) can
# replace it with `services.ssh-agent.enable = false;` in home/.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  defaults = import ../../lib/defaults.nix { inherit lib; };
  confirm = config.nixod.home.ssh.confirm;
in
{
  options.nixod.home.ssh.confirm = lib.mkEnableOption ''
    a confirmation dialog each time a key in the ssh-agent is used: every
    commit signature and every login to the hub then needs a click. It is a
    human check on what the agent signs. It only protects a key with a
    passphrase (without one, signing reads the key file directly, no agent
    involved). Needs the X11 desktop (the dialog is graphical)'';

  config = lib.mkMerge [
    (defaults {
      services.ssh-agent.enable = true;

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        # Adds keys to the agent on first use.
        settings."*".AddKeysToAgent = "yes";
      };
    })

    (lib.mkIf confirm {
      assertions = [
        {
          assertion = osConfig.nixod.profiles.x11.enable;
          message = "nixod.home.ssh.confirm needs the X11 desktop (nixod.profiles.x11): its dialog is graphical.";
        }
      ];

      # Keys added on first use (ssh, or `ssh-add -c` by hand) need a
      # confirmation at each use.
      programs.ssh.settings."*".AddKeysToAgent = "confirm";

      # ssh-agent shows the dialog itself, with its own environment: give it
      # the askpass program, and start it inside the graphical session so it
      # has DISPLAY.
      systemd.user.services.ssh-agent = {
        Service.Environment = [ "SSH_ASKPASS=${pkgs.x11_ssh_askpass}/libexec/x11-ssh-askpass" ];
        Unit = {
          After = [ "graphical-session-pre.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
      };
    })
  ];
}
