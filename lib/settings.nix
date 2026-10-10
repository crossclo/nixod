# What settings.nix must contain before any machine can be built.
# Each path here is marked `# NIXOD:FILL` in template/settings.nix
# (tests/default.nix checks that the two lists stay in sync).
{ lib }:

let
  required = [
    [
      "user"
      "name"
    ]
    [
      "user"
      "fullName"
    ]
    [
      "user"
      "email"
    ]
    [ "timeZone" ]
    [
      "keyboard"
      "console"
    ]
    [
      "keyboard"
      "xkb"
    ]
    [
      "repo"
      "url"
    ]
  ];
in
rec {
  inherit required;

  # One message per required setting that is still null (or absent).
  missingSettings =
    settings:
    map (path: "settings.${lib.concatStringsSep "." path} is not set") (
      lib.filter (path: lib.attrByPath path null settings == null) required
    );

  missingMessage =
    missing:
    "nixod: settings.nix is incomplete (look for NIXOD:FILL):\n"
    + lib.concatMapStrings (m: "  - ${m}\n") missing;
}
