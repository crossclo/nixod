{
  user = {
    name = "alice";
    fullName = "Alice Example";
    email = "alice@example.org";
  };

  timeZone = "Etc/UTC";
  locale = "en_US.UTF-8";
  extraLocaleSettings.LC_TIME = "en_GB.UTF-8";

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
