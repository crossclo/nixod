#!/usr/bin/env bash
# nixod identity host <name>   (on a new host)
# nixod identity hub <name>    (on the first host, for the hub)
#
# Creates a machine's identities, or reuses existing ones, and prints their
# public parts as Nix, for the machine's entry in network.nix.
#   host: Syncthing identity in ~/.config/syncthing, and this machine's own
#         nixod SSH key ~/.ssh/nixod_ed25519 (logs into the hub as root, signs
#         commits). Never a key shared with another machine: removing a
#         machine revokes its key.
#   hub:  Syncthing identity, SSH host key and read-only deploy key, in a
#         staging dir laid out like the hub's root file system. Keep it on
#         tmpfs: `nixod install-hub` copies it to the hub, then deletes it.
#         --console-password asks for the hub's console password and stages
#         its hash too (never in the repo).
# Nothing private is ever written to the repo.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

usage() {
  cat <<'EOF'
Usage: nixod identity host <name> [--key PATH] [--passphrase] [--dry-run]
       nixod identity hub <name> [--staging DIR] [--console-password] [--dry-run]

  --key PATH          host: SSH key to use or create (default ~/.ssh/nixod_ed25519)
  --passphrase        host: let ssh-keygen ask for a passphrase (needs a
                      terminal). Without it the key has none, so the agent
                      can sign and reach the hub; add one later with
                      ssh-keygen -p -f <key>
  --staging DIR       hub: where to put its keys (default
                      $XDG_RUNTIME_DIR/nixod/hub-<name>, a tmpfs)
  --console-password  hub: ask for the hub's console password (twice, needs
                      a terminal) and stage its yescrypt hash
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

key=$HOME/.ssh/nixod_ed25519
staging=
passphrase=0
console_password=0
while [[ $# -gt 0 ]]; do
  case $1 in
  --key) key=$2 && shift ;;
  --staging) staging=$2 && shift ;;
  --passphrase) passphrase=1 ;;
  --console-password) console_password=1 ;;
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
    ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1 ||
      warn "$key has a passphrase: signing and logging into the hub need it loaded in an ssh-agent (ssh-add, in a terminal)"
  else
    run install -d -m 700 "$(dirname "$key")"
    if [[ $passphrase == 0 ]]; then
      run ssh-keygen -q -t ed25519 -N "" -C "$(id -un)@$name" -f "$key"
    else
      [[ -t 0 || $DRY_RUN == 1 ]] ||
        die "ssh-keygen needs a terminal to ask for a passphrase: let the user run it in a terminal, or leave out --passphrase."
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

# console_password_hash <file>: asks for the hub's console password, twice,
# and writes its yescrypt hash to <file>. The password itself goes nowhere.
console_password_hash() {
  local file=$1 pw pw2
  step "The hub's console password (provider console only; the way back in, see nixod doc recover)"
  if [[ $DRY_RUN == 1 ]]; then
    run mkpasswd --method=yescrypt --stdin ">" "$file"
    return
  fi
  [[ -t 0 ]] || die "the console password is typed by the user: let them run this in a terminal"
  read -r -s -p "Console password: " pw && echo >&2
  read -r -s -p "Again: " pw2 && echo >&2
  [[ -n $pw ]] || die "empty password, nothing written"
  [[ $pw == "$pw2" ]] || die "the two passwords differ, nothing written"
  (umask 077 && printf '%s' "$pw" | mkpasswd --method=yescrypt --stdin >"$file")
  info "hash written to $file"
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

  if [[ $console_password == 1 ]]; then
    console_password_hash "$staging/var/lib/nixod/console-password"
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
