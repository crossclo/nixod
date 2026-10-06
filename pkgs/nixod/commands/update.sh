#!/usr/bin/env bash
# nixod update   (hosts, run by the user)
#
# Fetches, verifies the new commit like the hub does, fast-forwards the
# user's clone, then switches this machine to it. Stops, and says why, if the
# clone has uncommitted changes or commits that aren't on the remote.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

while [[ $# -gt 0 ]]; do
  case $1 in
  --dry-run) DRY_RUN=1 ;;
  -h | --help)
    echo "Usage: nixod update [--dry-run]"
    exit 0
    ;;
  *) die "unknown option: $1" ;;
  esac
  shift
done

[[ -n ${NIXOD_NAME:-} ]] || die "NIXOD_NAME is not set (/etc/nixod/config)"
clone=$(expand_home "${NIXOD_REPO_PATH:-~/nixod}")
[[ -d $clone/.git ]] || die "no clone at $clone (settings.repo.path)"

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

if [[ $new == "$cur" && $(git -C "$clone" rev-parse HEAD) == "$new" ]]; then
  info "up to date at $cur"
  exit 0
fi

step "Fast-forward to $new"
run git -C "$clone" merge --quiet --ff-only "$new"

step "Switch this machine"
if [[ -n ${NIXOD_APPLY:-} ]]; then
  run "$NIXOD_APPLY" "$clone" "$new"
else
  run sudo nixos-rebuild switch --flake "$clone#$NIXOD_NAME"
fi
