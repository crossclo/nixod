# The nixod CLI in the build sandbox: --dry-run prints the steps and changes
# nothing; `identity host` creates, then reuses, and prints importable Nix;
# prompts that need a terminal refuse without one.
{ self, pkgs }:

let
  nixod = self.packages.${pkgs.stdenv.hostPlatform.system}.nixod;
in
pkgs.runCommand "nixod-cli"
  {
    nativeBuildInputs = [
      nixod
      pkgs.openssh
      pkgs.mkpasswd
    ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    expect() { # expect <pattern> <file>
      grep -qF -- "$1" "$2" || { echo "expected '$1' in:"; cat "$2"; exit 1; }
    }

    # ---- --dry-run: prints, creates nothing ----
    nixod identity host tower --dry-run 2>dry
    expect "syncthing generate" dry
    expect "ssh-keygen -q -t ed25519" dry
    nixod identity hub hub --dry-run --staging "$TMPDIR/staging" --console-password 2>dry
    expect "ssh_host_ed25519_key" dry
    expect "deploy_key" dry
    expect "mkpasswd --method=yescrypt --stdin" dry
    nixod probe root@203.0.113.10 --dry-run 2>dry
    expect "ssh -o BatchMode=yes root@203.0.113.10 sh -s" dry
    nixod install-hub hub root@203.0.113.10 --stage hardware --dry-run 2>dry
    expect "--phases kexec" dry
    expect "--generate-hardware-config nixos-generate-config hosts/hub/hardware-configuration.nix" dry
    nixod install-hub hub root@203.0.113.10 --stage install --dry-run --staging "$TMPDIR/staging" 2>dry
    expect "nix --extra-experimental-features" dry
    expect "gh repo deploy-key add" dry
    expect "--chown /var/lib/syncthing" dry
    expect "rm -rf $TMPDIR/staging" dry
    expect "ssh-keygen -R 203.0.113.10" dry
    test ! -e "$HOME/.ssh" && test ! -e "$HOME/.config" && test ! -e "$TMPDIR/staging"

    # ---- identity host: creates (no passphrase), prints Nix, then reuses ----
    nixod identity host tower >first.nix 2>/dev/null
    test -s "$HOME/.ssh/nixod_ed25519" && test -s "$HOME/.config/syncthing/cert.pem"
    test "$(stat -c %a "$HOME/.config/syncthing/key.pem")" = 600
    ssh-keygen -y -P "" -f "$HOME/.ssh/nixod_ed25519" >/dev/null
    nixod identity host tower >second.nix 2>/dev/null
    cmp first.nix second.nix

    # ---- an existing key with a passphrase: kept, with a warning ----
    rm -rf "$HOME/.ssh"
    mkdir -m 700 "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N "secret" -f "$HOME/.ssh/nixod_ed25519"
    nixod identity host tower >/dev/null 2>err
    expect "has a passphrase" err

    # ---- --passphrase or --console-password without a terminal: refuses ----
    rm -rf "$HOME/.ssh"
    if nixod identity host tower --passphrase </dev/null 2>err; then exit 1; fi
    expect "needs a terminal" err
    if nixod identity hub hub --staging "$TMPDIR/staging" --console-password </dev/null 2>err; then exit 1; fi
    expect "typed by the user" err
    test ! -e "$TMPDIR/staging/var/lib/nixod/console-password"

    # ---- the hash the console password is staged as ----
    printf 'pw' | mkpasswd --method=yescrypt --stdin | grep -q '^\$y\$'

    # ---- install-hub without a console password: refuses before anything ----
    if nixod install-hub hub root@203.0.113.10 --stage install --staging "$TMPDIR/staging" --yes 2>err; then exit 1; fi
    expect "no console password staged" err

    mkdir -p $out
    cp first.nix $out/host.nix
  ''
