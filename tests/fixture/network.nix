# Placeholder IDs and keys: valid format, no private key behind them.
{
  machines = {
    hub = {
      role = "hub";
      address = "203.0.113.10";
      syncthingId = "HUBAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA";
      sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderHubHostKey00000000000000000000";
      deployKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderHubDeployKey0000000000000000000";
    };
    tower = {
      role = "host";
      syncthingId = "TOWERAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA";
      userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderTowerUserKey000000000000000000 alice@tower";
      folders = {
        projects = "/home/alice/sync/projects";
        docs = "/home/alice/sync/docs";
      };
    };
  };

  folders = {
    projects.versioning = {
      type = "staggered";
      params.maxAge = "2592000";
    };
    docs.versioning = {
      type = "staggered";
      params.maxAge = "31536000";
    };
  };
}
