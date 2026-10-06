# The network.nix schema. `errors` returns one message per problem, so
# `nix flake check` can list them all at once.
{ lib }:

let
  # 8 groups of 7 base32 characters.
  syncthingIdRe = "([A-Z2-7]{7}-){7}[A-Z2-7]{7}";
  sshKeyRe = "ssh-ed25519 [A-Za-z0-9+/]+=*( .*)?";
  hostNameRe = "[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?";

  fields = {
    hub = [
      "role"
      "address"
      "syncthingId"
      "sshHostKey"
      "deployKey"
    ];
    host = [
      "role"
      "syncthingId"
      "userKey"
      "folders"
    ];
  };
  optionalFields = [ "folders" ];

  matches = re: s: lib.isString s && builtins.match re s != null;

  machineErrors =
    folders: name: m:
    let
      at = "machines.${name}";
      role = m.role or null;
      known = fields.${role} or null;
    in
    if known == null then
      [ "${at}.role must be \"host\" or \"hub\"" ]
    else
      lib.optional (!matches hostNameRe name) "${at}: \"${name}\" is not a valid host name"
      ++ map (k: "${at}.${k} is missing") (
        lib.filter (k: !(m ? ${k}) && !(lib.elem k optionalFields)) known
      )
      ++ map (k: "${at}.${k} is not a field of a ${role}") (
        lib.filter (k: !(lib.elem k known)) (lib.attrNames m)
      )
      ++ lib.optional (
        m ? syncthingId && !matches syncthingIdRe m.syncthingId
      ) "${at}.syncthingId is not a Syncthing device ID"
      ++
        lib.concatMap
          (
            k: lib.optional (m ? ${k} && !matches sshKeyRe m.${k}) "${at}.${k} is not an ssh-ed25519 public key"
          )
          [
            "sshHostKey"
            "deployKey"
            "userKey"
          ]
      ++ lib.concatLists (
        lib.mapAttrsToList (
          id: path:
          lib.optional (!(folders ? ${id})) "${at}.folders.${id}: there is no folder \"${id}\" in folders"
          ++ lib.optional (
            !(lib.isString path && lib.hasPrefix "/" path)
          ) "${at}.folders.${id} must be an absolute path"
        ) (m.folders or { })
      );
in
{
  errors =
    network:
    let
      machines = network.machines or { };
      folders = network.folders or { };
      hubCount = lib.count (m: (m.role or null) == "hub") (lib.attrValues machines);
      ids = lib.filter lib.isString (map (m: m.syncthingId or null) (lib.attrValues machines));
      duplicateIds = lib.unique (lib.filter (id: lib.count (x: x == id) ids > 1) ids);
    in
    map (k: "${k}: unknown top-level field") (
      lib.attrNames (
        removeAttrs network [
          "machines"
          "folders"
          "recovery"
        ]
      )
    )
    ++ lib.concatLists (lib.mapAttrsToList (machineErrors folders) machines)
    ++ lib.optional (
      machines != { } && hubCount != 1
    ) "there must be exactly one hub (found ${toString hubCount})"
    ++ map (id: "Syncthing ID ${id} is used by more than one machine") duplicateIds
    ++ lib.optional (
      network ? recovery && !matches sshKeyRe (network.recovery.key or null)
    ) "recovery.key is not an ssh-ed25519 public key";

  message =
    errors: "nixod: network.nix is invalid:\n" + lib.concatMapStrings (e: "  - ${e}\n") errors;
}
