#!/usr/bin/env bash
# nixod remove <name>   (on a trusted host, in its clone)
#
# Removes a machine (lost, sold, broken), once its entry has been deleted
# from network.nix by hand: checks that, deletes hosts/<name>/, builds the
# hub, commits (signed) and pushes. When the hub applies it, the machine can
# no longer sync with it, log into it, or sign updates.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

usage() {
  cat <<'EOF'
Usage: nixod remove <name> [--no-build] [--dry-run]

Delete machines.<name> from network.nix first; this does the rest.
EOF
}

name=
build=1
while [[ $# -gt 0 ]]; do
  case $1 in
  --no-build) build=0 ;;
  --dry-run) DRY_RUN=1 ;;
  -h | --help) usage && exit 0 ;;
  -*) die "unknown option: $1" ;;
  *)
    [[ -z $name ]] || die "unexpected argument: $1"
    name=$1
    ;;
  esac
  shift
done
[[ -n $name ]] || {
  usage >&2
  exit 2
}
cd "$(git rev-parse --show-toplevel)"

step "Check machines.$name is deleted from network.nix"
committed=$(mktemp)
trap 'rm -f "$committed"' EXIT
git show HEAD:network.nix >"$committed"
role=$(nix_ eval --raw --file "$committed" "machines.$name.role" 2>/dev/null) ||
  die "machines.$name is not in the committed network.nix: nothing to remove"
[[ $role == host ]] || die "$name is the hub: it can't be removed (reinstalling it would wipe its data)"
if nix_ eval --file network.nix "machines.$name" >/dev/null 2>&1; then
  die "machines.$name is still in network.nix: delete its entry first"
fi
[[ $(git symbolic-ref --short -q HEAD || true) == "$NIXOD_BRANCH" ]] || die "not on $NIXOD_BRANCH"
others=$(git status --porcelain -- . ":(exclude)network.nix" ":(exclude)hosts/$name")
[[ -z $others ]] || die "other uncommitted changes: commit them separately first"$'\n'"$others"

step "Delete hosts/$name/"
if [[ -d hosts/$name ]]; then run git rm -r -q "hosts/$name"; else info "no hosts/$name/"; fi
run git add network.nix

if [[ $build == 1 ]]; then
  # shellcheck disable=SC2016 # a Nix expression, not shell
  hub=$(nix_ eval --raw --file network.nix machines \
    --apply 'ms: builtins.head (builtins.filter (n: ms.${n}.role == "hub") (builtins.attrNames ms))')
  step "Build the hub (it stops trusting $name)"
  run nix_ build --no-link ".#nixosConfigurations.$hub.config.system.build.toplevel"
fi

step "Check $NIXOD_BRANCH is verified (the signed commit vouches for it too)"
[[ $DRY_RUN == 1 ]] || check_base . HEAD

step "Commit, signed by this machine"
run git commit --quiet -S -m "nixod: remove $name"

step "Push $NIXOD_BRANCH"
run git push --quiet origin "$NIXOD_BRANCH" ||
  die "push refused: pull (git pull) and run nixod remove again"

step "Next"
info "The hub applies it within minutes; other hosts at their next update."
info "Also revoke $name's GitHub access (its SSH key, its gh login): it can still read the repo."
