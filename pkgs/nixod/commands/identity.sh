#!/usr/bin/env bash
# nixod identity host <name>   (on a new host)
# nixod identity hub <name>    (on the first host, for the hub)
#
# Creates a machine's identities, or reuses existing ones, and prints their
# public parts as Nix, for the machine's entry in network.nix.
#   host: Syncthing identity in ~/.config/syncthing, SSH key ~/.ssh/id_ed25519
#         (logs into the hub, signs commits).
#   hub:  Syncthing identity, SSH host key and read-only deploy key, in a
#         staging dir laid out like the hub's root file system. Keep it on
#         tmpfs: `nixod install-hub` copies it to the hub, then deletes it.
# Nothing private is ever written to the repo.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

usage() {
  cat <<'EOF'
Usage: nixod identity host <name> [--key PATH] [--no-passphrase] [--dry-run]
       nixod identity hub <name> [--staging DIR] [--dry-run]

  --key PATH        host: SSH key to use or create (default ~/.ssh/id_ed25519)
  --no-passphrase   host: create the SSH key without a passphrase (needed
                    without a terminal; otherwise ssh-keygen asks for one)
  --staging DIR     hub: where to put its keys (default
                    $XDG_RUNTIME_DIR/nixod/hub-<name>, a tmpfs)
EOF
}

kind=${1:-}
name=${2:-}
[[ $kind == -h || $kind == --help ]] && {
  usage
  exit 0
}
[[ ($kind == host || $kind == hub) && -n $name ]] || {
  usage >&2
  exit 2
}
shift 2

key=$HOME/.ssh/id_ed25519
staging=
no_passphrase=0
while [[ $# -gt 0 ]]; do
  case $1 in
  --key) key=$2 && shift ;;
  --staging) staging=$2 && shift ;;
  --no-passphrase) no_passphrase=1 ;;
  --dry-run) DRY_RUN=1 ;;
  -h | --help) usage && exit 0 ;;
  *) die "unknown option: $1" ;;
  esac
  shift
done

identity_host() {
  local st=$HOME/.config/syncthing

  step "Syncthing identity ($st)"
  if [[ -e $st/cert.pem && -e $st/key.pem ]]; then
    info "exists, kept"
  else
    new_syncthing_identity "$st"
  fi

  step "SSH key ($key): logs into the hub and signs commits"
  if [[ -e $key ]]; then
    info "exists, kept"
  else
    run install -d -m 700 "$(dirname "$key")"
    if [[ $no_passphrase == 1 ]]; then
      run ssh-keygen -q -t ed25519 -N "" -C "$(id -un)@$name" -f "$key"
    else
      [[ -t 0 || $DRY_RUN == 1 ]] ||
        die "ssh-keygen needs a terminal to ask for a passphrase. Let the user run it, or pass --no-passphrase."
      run ssh-keygen -t ed25519 -C "$(id -un)@$name" -f "$key"
    fi
  fi

  step "Public parts, for machines.$name in network.nix"
  [[ $DRY_RUN == 1 ]] && return
  cat <<EOF
# machines.$name in network.nix (add role = "host" and its folders)
{
  syncthingId = "$(syncthing_id "$st")";
  userKey = "$(public_key "$key.pub")";
}
EOF
}

identity_hub() {
  local st ssh_key deploy_key fstype

  if [[ -z $staging ]]; then
    [[ -n ${XDG_RUNTIME_DIR:-} ]] || die "XDG_RUNTIME_DIR is not set: pass --staging DIR (on a tmpfs)"
    staging=$XDG_RUNTIME_DIR/nixod/hub-$name
  fi
  st=$staging/var/lib/syncthing/.config/syncthing
  ssh_key=$staging/etc/ssh/ssh_host_ed25519_key
  deploy_key=$staging/var/lib/nixod/deploy_key

  step "Staging dir ($staging)"
  # Modes matter: the tree is copied as is onto the hub's root.
  umask 022
  run install -d -m 700 "$staging"
  run install -d -m 755 "$staging/etc/ssh" "$staging/var/lib"
  run install -d -m 700 "$staging/var/lib/syncthing" "$staging/var/lib/nixod"
  if [[ $DRY_RUN == 0 ]]; then
    fstype=$(findmnt -n -o FSTYPE --target "$staging" 2>/dev/null || true)
    [[ $fstype == tmpfs ]] || warn "$staging is on '${fstype:-unknown}', not tmpfs: the hub's private keys touch the disk"
  fi

  step "Syncthing identity"
  if [[ -e $st/cert.pem ]]; then info "exists, kept"; else new_syncthing_identity "$st"; fi

  step "SSH host key (known by every machine)"
  if [[ -e $ssh_key ]]; then
    info "exists, kept"
  else
    run ssh-keygen -q -t ed25519 -N "" -C "root@$name" -f "$ssh_key"
  fi

  step "Deploy key (read-only access to the repo, for the hub's updates)"
  if [[ -e $deploy_key ]]; then
    info "exists, kept"
  else
    run ssh-keygen -q -t ed25519 -N "" -C "nixod-deploy@$name" -f "$deploy_key"
  fi

  step "Public parts, for machines.$name in network.nix"
  [[ $DRY_RUN == 1 ]] && return
  cat <<EOF
# machines.$name in network.nix (add role = "hub" and its address)
{
  syncthingId = "$(syncthing_id "$st")";
  sshHostKey = "$(public_key "$ssh_key.pub")";
  deployKey = "$(public_key "$deploy_key.pub")";
}
EOF
}

"identity_$kind"
