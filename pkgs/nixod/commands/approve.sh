#!/usr/bin/env bash
# nixod approve <pr number | branch>   (on a trusted host, after nixod review)
#
# Merges the reviewed join request into the branch with a commit signed by
# this machine (git merge --no-ff -S), and pushes. The hub only applies
# signed commits: this signature is what lets the new host in. Refuses if
# the request changed since it was reviewed. GitHub marks the PR merged.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

usage() {
  cat <<'EOF'
Usage: nixod approve <pr number | branch> [--dry-run]
EOF
}

id=
while [[ $# -gt 0 ]]; do
  case $1 in
  --dry-run) DRY_RUN=1 ;;
  -h | --help) usage && exit 0 ;;
  -*) die "unknown option: $1" ;;
  *)
    [[ -z $id ]] || die "unexpected argument: $1"
    id=$1
    ;;
  esac
  shift
done
[[ -n $id ]] || {
  usage >&2
  exit 2
}
cd "$(git rev-parse --show-toplevel)"

step "Fetch the request and $NIXOD_BRANCH"
head=$(fetch_request "$id")
marker=$(review_marker "$id")
reviewed=$(cat "$marker" 2>/dev/null) || die "not reviewed: run nixod review $id first"
[[ $head == "$reviewed" ]] ||
  die "the request changed since the review (reviewed $reviewed, now $head): review it again"

step "Check the clone"
[[ -z $(git status --porcelain) ]] || die "uncommitted changes: commit or stash them first"
run git switch --quiet "$NIXOD_BRANCH"
run git merge --quiet --ff-only "refs/remotes/origin/$NIXOD_BRANCH" ||
  die "local $NIXOD_BRANCH has commits that are not pushed: push them first"
step "Check $NIXOD_BRANCH is verified (the merge vouches for it too)"
[[ $DRY_RUN == 1 ]] || check_base . HEAD

step "Merge $head, signed by this machine"
if ! run git merge --quiet --no-ff -S -m "nixod: approve join request $id" "$head"; then
  git merge --abort 2>/dev/null || true
  die "the request does not merge cleanly into $NIXOD_BRANCH: ask the new host to update it"
fi

step "Push $NIXOD_BRANCH"
if ! run git push --quiet origin "$NIXOD_BRANCH"; then
  git reset --quiet --hard "refs/remotes/origin/$NIXOD_BRANCH"
  die "push refused: someone pushed meanwhile. The merge was undone locally: run nixod approve $id again"
fi
run rm -f "$marker"

step "Next"
info "The hub applies it within minutes (nixod status on the hub)."
info "Then the new host, in its clone (the user, in a terminal):"
info "  nix run .#nixod -- update --first <its name>, then reboot"
