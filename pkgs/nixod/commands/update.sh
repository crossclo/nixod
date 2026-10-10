#!/usr/bin/env bash
# nixod update   (hosts, run by the user)
#
# Fetches, verifies the new commit like the hub does, fast-forwards the
# user's clone, then switches this machine to it. Stops, and says why, if the
# clone has uncommitted changes or commits that aren't on the remote.
#
# --first <name>: right after a join, on a machine that doesn't run nixod yet
# (run it in the clone). It has no trusted keys of its own: it trusts the
# hosts in network.nix of the join request it sent (join/<name>), so the
# approval must be signed by one of them. Then `nixos-rebuild boot` (the
# first switch needs a reboot).
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

first=
while [[ $# -gt 0 ]]; do
  case $1 in
  --dry-run) DRY_RUN=1 ;;
  --first) first=$2 && shift ;;
  -h | --help)
    echo "Usage: nixod update [--dry-run]"
    echo "       nixod update --first <name>   (right after a join, in the clone)"
    exit 0
    ;;
  *) die "unknown option: $1" ;;
  esac
  shift
done

if [[ -n $first ]]; then
  [[ ! -e /etc/nixod/config ]] || die "this machine already runs nixod: nixod update, without --first"
  NIXOD_NAME=$first
  clone=$(git rev-parse --show-toplevel 2>/dev/null) || die "run it in the clone of the repo"
  join=$(git -C "$clone" rev-parse -q --verify "refs/heads/join/$first") ||
    die "no branch join/$first here: --first is for the machine that sent the join request"
  # Trust: the hosts of the network as this machine's own request saw it.
  NIXOD_SIGNERS=$(mktemp)
  trap 'rm -f "$NIXOD_SIGNERS"' EXIT
  signers_at "$clone" "$join" >"$NIXOD_SIGNERS" || die "can't read the hosts in network.nix of join/$first"
  running_rev() { printf '%s' "$join"; }
else
  [[ -n ${NIXOD_NAME:-} ]] || die "NIXOD_NAME is not set (/etc/nixod/config)"
  clone=$(expand_home "${NIXOD_REPO_PATH:-~/nixod}")
  [[ -d $clone/.git ]] || die "no clone at $clone (settings.repo.path)"
fi

step "Fetch $NIXOD_BRANCH in $clone"
run git -C "$clone" fetch --quiet origin "$NIXOD_BRANCH"
new=$(git -C "$clone" rev-parse "refs/remotes/origin/$NIXOD_BRANCH")

cur=$(running_rev)
[[ -n $cur ]] || cur=$(git -C "$clone" rev-parse HEAD)

if [[ $new != "$cur" ]]; then
  step "Verify $new"
  reason=$(verify "$clone" "$cur" "$new" "$NIXOD_SIGNERS") || die "update rejected: $reason"
  info "signed by a trusted machine, builds on the running commit"
fi

step "Check the clone"
[[ -z $(git -C "$clone" status --porcelain) ]] ||
  die "uncommitted changes in $clone: commit (and push) or stash them first"
git -C "$clone" merge-base --is-ancestor HEAD "$new" ||
  die "$clone has commits that are not on origin/$NIXOD_BRANCH: push them first (or rebase on it)"
# Right after a join, the clone is still on its join/<name> branch.
if [[ $(git -C "$clone" symbolic-ref --short -q HEAD || true) != "$NIXOD_BRANCH" ]]; then
  step "Switch the clone to $NIXOD_BRANCH"
  if git -C "$clone" show-ref --verify --quiet "refs/heads/$NIXOD_BRANCH"; then
    run git -C "$clone" switch --quiet "$NIXOD_BRANCH"
  else
    run git -C "$clone" switch --quiet --create "$NIXOD_BRANCH" --track "origin/$NIXOD_BRANCH"
  fi
  [[ $DRY_RUN == 1 ]] || git -C "$clone" merge-base --is-ancestor HEAD "$new" ||
    die "local $NIXOD_BRANCH has commits that are not on origin/$NIXOD_BRANCH: push them first"
fi

if [[ $new == "$cur" && $(git -C "$clone" rev-parse HEAD) == "$new" ]]; then
  info "up to date at $cur"
  exit 0
fi

step "Fast-forward to $new"
run git -C "$clone" merge --quiet --ff-only "$new"

step "Switch this machine"
if [[ -n ${NIXOD_APPLY:-} ]]; then
  run "$NIXOD_APPLY" "$clone" "$new"
elif [[ -n $first ]]; then
  # The first switch changes the desktop: the new system starts at the reboot.
  run sudo nixos-rebuild boot --flake "$clone#$NIXOD_NAME"
  info "Done: reboot to start the new system."
else
  run sudo nixos-rebuild switch --flake "$clone#$NIXOD_NAME"
fi
