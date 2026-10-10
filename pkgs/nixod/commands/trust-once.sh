#!/usr/bin/env bash
# nixod trust-once <ssh-ed25519 public key>   (the hub, provider console ONLY)
#
# Recovery when every host is lost: the hub accepts ONE update signed by this
# key (the new host's userKey), then forgets it, whatever the result. The new
# host's commit adds it to network.nix for good.
#
# Refused over SSH: if someone could log into the hub, a lost host could
# still be trusted. Only the provider's console (VNC/serial) may do this:
# the login session must be a local one (logind's Remote=no). The check is on
# the session, not the terminal: `sudo -i` keeps the session, but runs the
# shell on a pseudo-terminal (sudo's use_pty).
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

[[ ${1:-} == -h || ${1:-} == --help ]] && {
  echo "Usage: nixod trust-once --from <name>              (as root, on the hub's console)"
  echo "       nixod trust-once 'ssh-ed25519 AAAA...'"
  echo
  echo "  --from <name>   read machines.<name>.userKey from network.nix on GitHub"
  echo "                  (the recovery commit, pushed first), show its fingerprint"
  echo "                  and ask to confirm it is the new machine's"
  exit 0
}
from=
key=
if [[ ${1:-} == --from ]]; then from=${2:-}; else key=${1:-}; fi

if [[ -n ${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-} ]]; then
  die "refused: this is an SSH session. Use the provider's console (VNC/serial)."
fi
[[ ${NIXOD_ROLE:-} == hub ]] || die "only on the hub"
[[ $EUID == 0 ]] || die "run as root"
session=$(loginctl show-session self -p Remote -p TTY 2>/dev/null) ||
  die "refused: not in a login session. Log in on the provider's console (VNC/serial) as the user, then sudo -i."
grep -qx 'Remote=no' <<<"$session" ||
  die "refused: this login session is remote (SSH). Use the provider's console (VNC/serial)."
info "local console session (${session//$'\n'/, })"
if [[ -n $from ]]; then
  step "Read machines.$from from network.nix on GitHub"
  repo=$NIXOD_STATE/repo
  GIT_SSH_COMMAND="ssh -i $NIXOD_STATE/deploy_key -o IdentitiesOnly=yes" \
    git -C "$repo" fetch --quiet --force origin "+refs/heads/$NIXOD_BRANCH:refs/remotes/origin/$NIXOD_BRANCH" ||
    die "can't fetch the repo from GitHub: pass the key itself instead"
  key=$(network_json_at "$repo" "refs/remotes/origin/$NIXOD_BRANCH" |
    jq -r --arg m "$from" '.machines[$m].userKey // empty') || true
  [[ -n $key ]] || die "machines.$from has no userKey in network.nix on GitHub: push the recovery commit first"
fi
[[ $key =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*(\ .*)?$ ]] || die "not an ssh-ed25519 public key: $key"
if [[ -n $from ]]; then
  echo "machines.$from on GitHub has this key:"
  ssh-keygen -lf - <<<"$key"
  echo "On the new machine, ssh-keygen -lf ~/.ssh/nixod_ed25519.pub must show the same."
  read -r -p "Type yes if they are the same: " answer
  [[ $answer == yes ]] || die "not confirmed, nothing done"
fi

step "Trust this key for the next update only"
install -d -m 700 "$NIXOD_STATE"
(
  umask 077
  printf '%s\n' "$key" >"$NIXOD_STATE/trust-once"
)
info "The next commit signed by this key is accepted once (within minutes"
info "of being pushed); then the key is removed. Unused, it expires in a day."
