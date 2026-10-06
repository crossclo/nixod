# Everything about how machines know each other, as pure functions of
# network.nix. Unit-tested in tests/derive.nix.
{ lib }:

let
  machinesOf = network: network.machines or { };

  # "ssh-ed25519 AAAA... comment" → "ssh-ed25519 AAAA..."
  keyOnly = key: lib.concatStringsSep " " (lib.take 2 (lib.splitString " " key));

  # IPv6 addresses go in brackets inside a URL.
  urlHost = address: if lib.hasInfix ":" address then "[${address}]" else address;
in
rec {
  hosts = network: lib.filterAttrs (_: m: m.role == "host") (machinesOf network);

  # The hub as { name, ...fields }, or null while there is none.
  hub =
    network:
    let
      hubs = lib.filterAttrs (_: m: m.role == "hub") (machinesOf network);
      name = lib.head (lib.attrNames hubs);
    in
    if hubs == { } then null else hubs.${name} // { inherit name; };

  # Every folder at least one host syncs, sorted.
  folderIds =
    network:
    lib.sort lib.lessThan (
      lib.unique (lib.concatMap (m: lib.attrNames (m.folders or { })) (lib.attrValues (hosts network)))
    );

  hubFolderPath = id: "/var/lib/syncthing/${id}";

  # Syncthing `settings.devices` and `settings.folders` for one machine.
  #   host: the hub (at its static address) + every other host; each of its
  #         folders, shared with the hub + every other host that has it.
  #   hub:  every host; every folder any host has, under /var/lib/syncthing,
  #         plus the folder's `hub.*` options.
  syncthing =
    network: name:
    let
      machine = network.machines.${name};
      h = hub network;
      allHosts = hosts network;
      device = _: m: { id = m.syncthingId; };
      # Folder-wide options from network.nix (versioning, label...).
      options = id: removeAttrs (network.folders.${id} or { }) [ "hub" ];
      hostsWith = id: lib.attrNames (lib.filterAttrs (_: m: (m.folders or { }) ? ${id}) allHosts);
    in
    if machine.role == "hub" then
      {
        devices = lib.mapAttrs device allHosts;
        folders = lib.genAttrs (folderIds network) (
          id:
          options id
          // (network.folders.${id}.hub or { })
          // {
            path = hubFolderPath id;
            devices = hostsWith id;
          }
        );
      }
    else
      {
        devices =
          lib.mapAttrs device (removeAttrs allHosts [ name ])
          // lib.optionalAttrs (h != null) {
            ${h.name} = {
              id = h.syncthingId;
              addresses = [
                "tcp://${urlHost h.address}:22000"
                "dynamic"
              ];
            };
          };
        folders = lib.mapAttrs (
          id: path:
          options id
          // {
            inherit path;
            devices = lib.optional (h != null) h.name ++ lib.remove name (hostsWith id);
          }
        ) (machine.folders or { });
      };

  # Directories to create before Syncthing starts. Inside the user's home,
  # every level is created (so ~/sync is the user's, not root's).
  folderDirs =
    network: name: home:
    let
      machine = network.machines.${name};
      levels =
        path:
        if lib.hasPrefix "${home}/" path then
          let
            parts = lib.splitString "/" (lib.removePrefix "${home}/" path);
          in
          lib.genList (i: "${home}/" + lib.concatStringsSep "/" (lib.take (i + 1) parts)) (lib.length parts)
        else
          [ path ];
    in
    if machine.role == "hub" then
      map hubFolderPath (folderIds network)
    else
      lib.unique (lib.concatMap levels (lib.attrValues (machine.folders or { })));

  # Keys that may log into the hub (root and the user): every host, plus
  # the recovery key.
  authorizedKeys =
    network:
    map (m: m.userKey) (lib.attrValues (hosts network))
    ++ lib.optional (network ? recovery) network.recovery.key;

  # programs.ssh.knownHosts on every machine: the hub's host key.
  knownHosts =
    network:
    let
      h = hub network;
    in
    lib.optionalAttrs (h != null) {
      ${h.name} = {
        hostNames = lib.unique [
          h.name
          h.address
        ];
        publicKey = keyOnly h.sshHostKey;
      };
    };

  # /etc/nixod/allowed_signers: the keys that may sign commits. One line per
  # host (principal = machine name), plus the recovery key.
  allowedSigners =
    network:
    lib.concatStrings (
      lib.mapAttrsToList (name: m: "${name} namespaces=\"git\" ${keyOnly m.userKey}\n") (hosts network)
      ++ lib.optional (network ? recovery) "recovery namespaces=\"git\" ${keyOnly network.recovery.key}\n"
    );
}
