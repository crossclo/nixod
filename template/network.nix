# Every machine in your network. Empty until the setup (init) adds the
# first host and the hub. Each machine needs a hosts/<name>/ directory.
# Plain data only: no imports, no file reads (a join request's network.nix is
# read as untrusted code, in Nix's restricted mode).
#
# machines.<name> for the hub (exactly one):
#   role = "hub"; address = "<public IP or DNS name>";
#   syncthingId = "..."; sshHostKey = "ssh-ed25519 ..."; deployKey = "ssh-ed25519 ...";
#
# machines.<name> for a host:
#   role = "host"; syncthingId = "..."; userKey = "ssh-ed25519 ...";
#   folders = { docs = "/home/<user>/sync/docs"; };   # folder name → path here
#
# folders.<name>: options shared by every machine that has the folder
# (Syncthing folder settings), plus `hub.*` for the hub only:
#   media = { versioning = { type = "trashcan"; params.cleanoutDays = "30"; };
#             hub.ignoreDelete = true; };
{
  machines = { };

  folders = { };
}
