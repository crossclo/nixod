# The nixod CLI in the build sandbox: --dry-run prints the steps and changes
# nothing; `identity host` creates, then reuses, and prints importable Nix.
{ self, pkgs }:

let
  nixod = self.packages.${pkgs.stdenv.hostPlatform.system}.nixod;
in
pkgs.runCommand "nixod-cli" { nativeBuildInputs = [ nixod ]; } ''
  set -euo pipefail
  export HOME=$TMPDIR/home
  mkdir -p "$HOME"
  expect() { # expect <pattern> <file>
    grep -qF -- "$1" "$2" || { echo "expected '$1' in:"; cat "$2"; exit 1; }
  }

  # ---- --dry-run: prints, creates nothing ----
  nixod identity host tower --dry-run --no-passphrase 2>dry
  expect "syncthing generate" dry
  expect "ssh-keygen -q -t ed25519" dry
  nixod identity hub hub --dry-run --staging "$TMPDIR/staging" 2>dry
  expect "ssh_host_ed25519_key" dry
  expect "deploy_key" dry
  nixod probe root@203.0.113.10 --dry-run 2>dry
  expect "ssh root@203.0.113.10 sh -s" dry
  nixod install-hub hub root@203.0.113.10 --stage hardware --dry-run 2>dry
  expect "--phases kexec" dry
  expect "--generate-hardware-config nixos-generate-config hosts/hub/hardware-configuration.nix" dry
  nixod install-hub hub root@203.0.113.10 --stage install --dry-run --staging "$TMPDIR/staging" 2>dry
  expect "nix --extra-experimental-features" dry
  expect "gh repo deploy-key add" dry
  expect "--chown /var/lib/syncthing 237:237" dry
  expect "rm -rf $TMPDIR/staging" dry
  test ! -e "$HOME/.ssh" && test ! -e "$HOME/.config" && test ! -e "$TMPDIR/staging"

  # ---- identity host: creates, prints Nix, then reuses ----
  nixod identity host tower --no-passphrase >first.nix 2>/dev/null
  test -s "$HOME/.ssh/id_ed25519" && test -s "$HOME/.config/syncthing/cert.pem"
  test "$(stat -c %a "$HOME/.config/syncthing/key.pem")" = 600
  nixod identity host tower --no-passphrase >second.nix 2>/dev/null
  cmp first.nix second.nix

  # ---- no terminal and no --no-passphrase: refuses instead of hanging ----
  rm -rf "$HOME/.ssh"
  if nixod identity host tower </dev/null 2>err; then exit 1; fi
  expect "needs a terminal" err

  mkdir -p $out
  cp first.nix $out/host.nix
''
