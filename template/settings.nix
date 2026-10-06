# Who you are. Your agent fills every marked line;
# `nix flake check` fails until they are all set.
{
  user = {
    name = null; # NIXOD:FILL  login name
    fullName = null; # NIXOD:FILL
    email = null; # NIXOD:FILL  git identity
  };

  timeZone = null; # NIXOD:FILL  e.g. "Europe/Paris"
  locale = "en_US.UTF-8";
  # extraLocaleSettings = { LC_TIME = "fr_FR.UTF-8"; };

  keyboard = {
    console = null; # NIXOD:FILL  console keymap, e.g. "fr" or "us"
    xkb = null; # NIXOD:FILL  X11 layout, e.g. "fr" or "us"
  };

  repo = {
    url = null; # NIXOD:FILL  git@github.com:<user>/nixod-config.git
    branch = "main";
    path = "~/nixod"; # where the clone lives on hosts
  };

  # Console login on the hub (provider VNC/serial console, never SSH).
  hub.hashedPassword = null; # NIXOD:FILL  mkpasswd -m sha-512
}
