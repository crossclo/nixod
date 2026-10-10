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
  echo "Usage: nixod trust-once 'ssh-ed25519 AAAA...'   (as root, on the hub's console)"
  exit 0
}
key=${1:-}

if [[ -n ${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-} ]]; then
  die "refused: this is an SSH session. Use the provider's console (VNC/serial)."
fi
[[ ${NIXOD_ROLE:-} == hub ]] || die "only on the hub"
[[ $EUID == 0 ]] || die "run as root"
[[ $key =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*(\ .*)?$ ]] || die "not an ssh-ed25519 public key: $key"
session=$(loginctl show-session self -p Remote -p TTY 2>/dev/null) ||
  die "refused: not in a login session. Log in on the provider's console (VNC/serial) as the user, then sudo -i."
grep -qx 'Remote=no' <<<"$session" ||
  die "refused: this login session is remote (SSH). Use the provider's console (VNC/serial)."
info "local console session (${session//$'\n'/, })"

step "Trust this key for the next update only"
install -d -m 700 "$NIXOD_STATE"
(
  umask 077
  printf '%s\n' "$key" >"$NIXOD_STATE/trust-once"
)
info "Push the new host's commit, signed with this key. The next check"
info "(within minutes) accepts it once, then removes the key."
