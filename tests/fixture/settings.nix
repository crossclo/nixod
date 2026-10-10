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
}
