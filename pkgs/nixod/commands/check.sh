#!/usr/bin/env bash
# nixod check   (hosts: the user's nixod-check.timer, and by hand)
#
# Fetches the repo in the user's clone (fetch only: the working tree is never
# touched) and checks the new commit like the hub does. A verified update
# shows a desktop notification ("3 changes ready: run nixod update"); a
# rejected one shows an urgent one with the reason.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

[[ ${1:-} == -h || ${1:-} == --help ]] && {
  echo "Usage: nixod check   (fetch and verify; never changes the working tree)"
  exit 0
}

clone=$(expand_home "${NIXOD_REPO_PATH:-~/nixod}")
[[ -d $clone/.git ]] || die "no clone at $clone (settings.repo.path)"

notify() { # notify <urgency> <title> <body>
  printf '%s: %s\n' "$2" "$3"
  "${NIXOD_NOTIFY:-notify-send}" -u "$1" -a nixod "$2" "$3" || true
}

step "Fetch $NIXOD_BRANCH in $clone"
git -C "$clone" fetch --quiet origin "$NIXOD_BRANCH"
new=$(git -C "$clone" rev-parse "refs/remotes/origin/$NIXOD_BRANCH")

cur=$(running_rev)
# A system built from a dirty tree has no revision: the user's own clone is
# the next best reference on a host.
[[ -n $cur ]] || cur=$(git -C "$clone" rev-parse HEAD)
if [[ $new == "$cur" ]]; then
  info "up to date at $cur"
  exit 0
fi

step "Verify $new"
if ! reason=$(verify "$clone" "$cur" "$new" "$NIXOD_SIGNERS"); then
  notify critical "nixod: update rejected" "$reason"
  exit 1
fi

count=$(git -C "$clone" rev-list --count "$cur..$new")
subjects=$(git -C "$clone" log --format='• %s' -n 5 "$cur..$new")
notify normal "nixod" "$count change(s) ready: run nixod update
$subjects"
