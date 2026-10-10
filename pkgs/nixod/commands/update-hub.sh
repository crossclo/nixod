#!/usr/bin/env bash
# nixod update-hub   (the hub's nixod-update.service, every few minutes)
#
# Fetches the repo into the hub's own clone, with the read-only deploy key,
# then applies the new commit only if:
#   1. it builds on the commit the hub runs (no rewritten history, no rollback);
#   2. it is signed by a trusted key: one in /etc/nixod/allowed_signers, from
#      the RUNNING system (a commit can't vouch for itself), as updated by the
#      signed commits in between (see `verify` in lib.sh), or the one-time key
#      that `nixod trust-once` set from the console: used up by the first new
#      commit signed by it, and dropped unused after a day.
# Otherwise, or if the build fails, the running system stays. The result goes
# to the journal and to /var/lib/nixod/status (`nixod status`).
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

[[ ${1:-} == -h || ${1:-} == --help ]] && {
  echo "Usage: nixod update-hub   (run by nixod-update.service on the hub)"
  exit 0
}
[[ -n ${NIXOD_REPO_URL:-} && -n ${NIXOD_NAME:-} ]] || die "NIXOD_REPO_URL and NIXOD_NAME must be set (/etc/nixod/config)"

repo=$NIXOD_STATE/repo
trust_once=$NIXOD_STATE/trust-once

record() { # record <result> <message>
  printf '%s %s %s\n' "$(date -Iseconds)" "$1" "$2" >"$NIXOD_STATE/status"
  printf '%s: %s\n' "$1" "$2"
}

step "Fetch $NIXOD_BRANCH from $NIXOD_REPO_URL"
mkdir -p "$NIXOD_STATE"
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$NIXOD_REPO_URL" "$repo"
git -C "$repo" fetch --quiet --force origin "+refs/heads/$NIXOD_BRANCH:refs/remotes/origin/$NIXOD_BRANCH"
new=$(git -C "$repo" rev-parse "refs/remotes/origin/$NIXOD_BRANCH")

cur=$(running_rev)
if [[ -z $cur ]]; then
  record error "the running commit is unknown (system not built from a clean commit)"
  exit 1
fi
if [[ $new == "$cur" ]]; then
  record ok "up to date at $cur"
  exit 0
fi

step "Verify $new"
signers=$NIXOD_SIGNERS
if [[ -e $trust_once && -n $(find "$trust_once" -mmin +1440 2>/dev/null) ]]; then
  rm -f "$trust_once"
  info "the trust-once key was set more than a day ago and never used: removed"
fi
if [[ -e $trust_once ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  printf 'trust-once namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$trust_once")" >"$tmp/once"
  # Used up by the first commit signed by it, accepted or not. Other commits
  # (pushed before the recovery commit) leave it waiting.
  if signed_by "$repo" "$new" "$tmp/once"; then
    cat "$NIXOD_SIGNERS" "$tmp/once" >"$tmp/signers"
    signers=$tmp/signers
    rm -f "$trust_once"
    info "$new is signed by the trust-once key: accepted for this check only (key now removed)"
  else
    info "a trust-once key is waiting for a commit signed by it"
  fi
fi
if ! reason=$(verify "$repo" "$cur" "$new" "$signers"); then
  record rejected "$reason"
  exit 1
fi

step "Switch to $new"
git -C "$repo" checkout --quiet --force --detach "$new"
if [[ -n ${NIXOD_APPLY:-} ]]; then
  apply=("$NIXOD_APPLY" "$repo" "$new")
else
  apply=(nixos-rebuild switch --flake "$repo#$NIXOD_NAME")
fi
if ! "${apply[@]}"; then
  record failed "applying $new failed: the previous system keeps running (see the journal)"
  exit 1
fi
printf '%s\n' "$new" >"$NIXOD_STATE/revision"
record ok "applied $new"
