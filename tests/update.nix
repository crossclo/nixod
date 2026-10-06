# Update verification, in the build sandbox, with the real commands against
# a local bare repo standing in for GitHub. Each case below is a commit (or a
# forced push) followed by the hub's check:
#   accepted: a signed fast-forward; a signed commit on top of unsigned ones
#             (only the tip must be signed); one trust-once commit
#   rejected: unsigned; signed by an unknown key; a rollback to an older
#             signed commit; rewritten history; a removed host's key; a second
#             trust-once commit; and a failed build keeps the running commit.
# Then the host side: `check` notifies (ready / rejected), `update` refuses a
# dirty or diverged clone and fast-forwards otherwise; `trust-once` refuses
# SSH sessions.
{ self, pkgs }:

let
  nixod = self.packages.${pkgs.stdenv.hostPlatform.system}.nixod;

  # Stands in for `nixos-rebuild switch`: records the commit, fails on demand.
  apply = pkgs.writeShellScript "apply" ''
    echo "$2" >>"$TMPDIR/applied"
    exit "''${APPLY_FAIL:-0}"
  '';
  notify = pkgs.writeShellScript "notify" ''
    echo "$*" >>"$TMPDIR/notifications"
  '';
in
pkgs.runCommand "nixod-update"
  {
    nativeBuildInputs = [
      nixod
      pkgs.git
      pkgs.openssh
    ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    cd "$TMPDIR"
    git config --global init.defaultBranch main
    git config --global user.name test
    git config --global user.email test@example.org
    git config --global gpg.format ssh

    expect() { # expect <text> <file>
      grep -qF -- "$1" "$2" || { echo "expected '$1' in $2:"; cat "$2"; exit 1; }
    }

    # tower is in network.nix; stranger is not.
    ssh-keygen -q -t ed25519 -N "" -C tower -f tower
    ssh-keygen -q -t ed25519 -N "" -C stranger -f stranger
    echo "tower namespaces=\"git\" $(cut -d' ' -f1,2 tower.pub)" >signers
    : >no-signers

    # "GitHub", and a clone where commits are made and pushed.
    git init -q --bare origin.git
    git clone -q origin.git work 2>/dev/null
    commit() { # commit <tower|stranger|unsigned> <message>
      echo "$2" >>work/log
      git -C work add log
      if [ "$1" = unsigned ]; then
        git -C work commit -q -m "$2"
      else
        git -C work -c user.signingkey="$TMPDIR/$1" commit -q -S -m "$2"
      fi
      git -C work push -q --force origin HEAD:main
      git -C work rev-parse HEAD
    }

    # ---- The hub ----
    export NIXOD_CONFIG=/dev/null NIXOD_NAME=hub NIXOD_ROLE=hub
    export NIXOD_REPO_URL=$TMPDIR/origin.git NIXOD_STATE=$TMPDIR/state
    export NIXOD_SIGNERS=$TMPDIR/signers NIXOD_APPLY=${apply}
    accepts() { nixod update-hub >hub.log 2>&1 || { echo "should be accepted:"; cat hub.log; exit 1; }; }
    rejects() { # rejects <expected reason>
      if nixod update-hub >hub.log 2>&1; then echo "should be rejected:"; cat hub.log; exit 1; fi
      expect "$1" state/status
    }
    revision() { cat state/revision; }

    base=$(commit tower base)
    mkdir -p state && echo "$base" >state/revision   # as installed

    accepts
    expect "ok up to date at $base" state/status

    c1=$(commit tower "signed fast-forward")
    accepts
    test "$(revision)" = "$c1"
    expect "$c1" applied

    commit unsigned "unsigned" >/dev/null
    rejects "rejected $(git -C work rev-parse HEAD) is not signed by a trusted machine"
    test "$(revision)" = "$c1"

    commit stranger "unknown key" >/dev/null
    rejects "is not signed by a trusted machine"

    # A trusted commit on top vouches for what is under it.
    c2=$(commit tower "signed tip over unsigned commits")
    accepts
    test "$(revision)" = "$c2"

    # Rollback: GitHub moved back to an older, signed commit.
    git -C work push -q --force origin "$c1:main"
    rejects "does not build on the running commit"
    test "$(revision)" = "$c2"

    # Rewritten history: a signed commit that doesn't descend from c2.
    git -C work checkout -q --orphan rewritten
    commit tower "rewritten history" >/dev/null
    git -C work push -q --force origin rewritten:main
    rejects "does not build on the running commit"
    git -C work checkout -q main
    git -C work reset -q --hard "$c2"
    git -C work push -q --force origin main:main

    # tower removed from network.nix: its key no longer verifies.
    c3=$(commit tower "after tower was removed")
    NIXOD_SIGNERS=$TMPDIR/no-signers rejects "is not signed by a trusted machine"

    # A failed build keeps the running commit; the next run retries.
    APPLY_FAIL=1 rejects "failed applying $c3 failed"
    test "$(revision)" = "$c2"
    accepts
    test "$(revision)" = "$c3"

    # trust-once: one commit signed by the new host's key, then forgotten.
    cp stranger.pub state/trust-once
    t1=$(commit stranger "trust-once")
    accepts
    test "$(revision)" = "$t1"
    test ! -e state/trust-once
    commit stranger "second trust-once commit" >/dev/null
    rejects "is not signed by a trusted machine"

    # trust-once is used up by a failed check too.
    commit unsigned "unsigned, while a trust-once key is set" >/dev/null
    cp stranger.pub state/trust-once
    rejects "is not signed by a trusted machine"
    test ! -e state/trust-once
    git -C work reset -q --hard "$t1"
    git -C work push -q --force origin main:main
    h1=$(commit tower "signed by tower again")

    # ---- A host (running c3; doesn't know the trust-once key) ----
    export NIXOD_NAME=tower NIXOD_ROLE=host NIXOD_STATE=$TMPDIR/host-state
    export NIXOD_REPO_PATH=$TMPDIR/clone NIXOD_NOTIFY=${notify}
    git clone -q origin.git clone 2>/dev/null
    git -C clone reset -q --hard "$c3"
    mkdir -p host-state && echo "$c3" >host-state/revision
    run_ok() { "$@" >cmd.log 2>&1 || { echo "failed: $*"; cat cmd.log; exit 1; }; }
    run_fails() { # run_fails <expected> <cmd...>
      local want=$1; shift
      if "$@" >cmd.log 2>&1; then echo "should fail: $*"; cat cmd.log; exit 1; fi
      expect "$want" cmd.log
    }

    run_ok nixod check
    expect "2 change(s) ready: run nixod update" notifications

    commit unsigned "unsigned, seen by a host" >/dev/null
    run_fails "update rejected" nixod check
    expect "critical -a nixod nixod: update rejected" notifications
    git -C work reset -q --hard "$h1"
    git -C work push -q --force origin main:main

    echo dirty >>clone/log
    run_fails "uncommitted changes" nixod update
    git -C clone checkout -q -- log

    git -C clone -c user.signingkey="$TMPDIR/tower" commit -q -S --allow-empty -m "local only"
    run_fails "commits that are not on origin/main" nixod update
    git -C clone reset -q --hard "$c3"

    : >applied
    run_ok nixod update
    test "$(git -C clone rev-parse HEAD)" = "$h1"
    expect "$h1" applied

    # ---- trust-once refuses SSH sessions, hosts and non-root ----
    key=$(cat stranger.pub)
    SSH_CONNECTION="198.51.100.7 50000 203.0.113.10 22" NIXOD_ROLE=hub run_fails "this is an SSH session" nixod trust-once "$key"
    NIXOD_ROLE=host run_fails "only on the hub" nixod trust-once "$key"
    NIXOD_ROLE=hub run_fails "run as root" nixod trust-once "$key"

    touch $out
  ''
