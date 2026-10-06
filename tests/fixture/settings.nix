{
  user = {
    name = "alice";
    fullName = "Alice Example";
    email = "alice@example.org";
  };

  timeZone = "Europe/Paris";
  locale = "en_US.UTF-8";
  extraLocaleSettings.LC_TIME = "fr_FR.UTF-8";

  keyboard = {
    console = "fr";
    xkb = "fr";
  };

  repo = {
    url = "git@github.com:alice/nixod-config.git";
    branch = "main";
    path = "~/nixod";
  };

  # Dummy hash (fixture only, matches no password).
  hub.hashedPassword = "$6$nixodtest$y1UQGaTgfVwmbBDq0E3n.iIq3jM2Vq1cS8QJHl3Q9lJ.v5pYyHq9yGqgdwN/3PZ5ZcG9Cqv2z5bLh2N3JmEy0.";
}
