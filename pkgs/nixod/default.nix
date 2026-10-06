{
  lib,
  stdenvNoCC,
  makeWrapper,
  shellcheck,
  bash,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  util-linux,
  openssh,
  syncthing,
  jq,
  git,
  gh,
  nix,
  nixos-anywhere,
}:

stdenvNoCC.mkDerivation {
  pname = "nixod";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./nixod
      ./lib.sh
      ./commands
      ./probe-remote.sh
    ];
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  dontBuild = true;

  doCheck = true;
  nativeCheckInputs = [ shellcheck ];
  checkPhase = ''
    runHook preCheck
    shellcheck -x -P SCRIPTDIR nixod lib.sh commands/*.sh probe-remote.sh
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/nixod $out/bin
    cp -r nixod lib.sh commands probe-remote.sh $out/libexec/nixod/
    chmod +x $out/libexec/nixod/nixod $out/libexec/nixod/commands/*.sh
    patchShebangs $out/libexec/nixod/nixod $out/libexec/nixod/commands
    # The system's own nix comes first (it talks to the local daemon).
    makeWrapper $out/libexec/nixod/nixod $out/bin/nixod \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          util-linux
          openssh
          syncthing
          jq
          git
          gh
          nixos-anywhere
        ]
      } \
      --suffix PATH : ${lib.makeBinPath [ nix ]}
    runHook postInstall
  '';

  meta = {
    description = "nixod's helper: identities, hub probe and install";
    mainProgram = "nixod";
  };
}
