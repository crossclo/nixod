# Phase 1 fixture: roles only. The full schema (IDs, keys, folders) comes
# with derive.nix.
{
  machines = {
    hub.role = "hub";
    tower.role = "host";
  };

  folders = { };
}
