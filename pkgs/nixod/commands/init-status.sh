#!/usr/bin/env bash
# nixod init-status [<name>]   (on the first host, in the repo)
#
# Where an init stands: checks each step of the init playbook against what
# the repo and the machines show, and prints the step to continue at. For an
# init interrupted halfway (session lost, logout, crash). Changes nothing.
# --offline skips the checks that need the network (GitHub, SSH to the VPS).
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

usage() {
  cat <<'EOF'
Usage: nixod init-status [<name>] [--hub NAME] [--staging DIR] [--key PATH] [--offline]

  <name>          this machine in network.nix (default: the host name)
  --hub NAME      the hub's name, while network.nix doesn't have it yet
                  (default: the directory in hosts/ with a disko.nix, else hub)
  --staging DIR   the hub's staged identity (default $XDG_RUNTIME_DIR/nixod/hub-<hub>)
  --key PATH      this machine's key (default ~/.ssh/nixod_ed25519)
  --offline       skip the GitHub and SSH checks (shown as "?")
EOF
}

name=
hub=
staging=
key=$HOME/.ssh/nixod_ed25519
offline=0
while [[ $# -gt 0 ]]; do
  case $1 in
  --hub) hub=$2 && shift ;;
  --staging) staging=$2 && shift ;;
  --key) key=$2 && shift ;;
  --offline) offline=1 ;;
  -h | --help) usage && exit 0 ;;
  -*) die "unknown option: $1" ;;
  *)
    [[ -z $name ]] || die "unexpected argument: $1"
    name=$1
    ;;
  esac
  shift
done
name=${name:-$(hostname)}
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo: run it in the clone of the instance repo"

# Plain files: no store needed to read them.
network=$(nix_ eval --store dummy:// --json --file network.nix 2>/dev/null) || network='{}'
in_network() { jq -e --arg m "$1" '.machines[$m] != null' <<<"$network" >/dev/null; }
if [[ -z $hub ]]; then
  hub=$(jq -r '[.machines // {} | to_entries[] | select(.value.role == "hub") | .key] | first // empty' <<<"$network")
fi
if [[ -z $hub ]]; then
  for d in hosts/*/disko.nix; do [[ -e $d ]] && hub=$(basename "$(dirname "$d")") && break; done
fi
hub=${hub:-hub}
address=$(jq -r --arg h "$hub" '.machines[$h].address // empty' <<<"$network")
staging=${staging:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nixod/hub-$hub}
branch=$(nix_ eval --store dummy:// --raw --file settings.nix repo.branch 2>/dev/null || echo main)

ssh_hub() { # ssh_hub <command...>: root on the VPS, with this machine's key, no prompt
  ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=10 "root@$address" "$@" >/dev/null 2>&1
}

# One state per step: 1 done, 0 not done, u unknown (offline, or no address).
declare -A state detail
mark() { state[$1]=$2 detail[$1]=${3:-}; }
online() { [[ $offline == 0 ]]; }

# Steps that only matter before the hub install count as done once it is.
hub_installed=u
if online && [[ -n $address ]]; then
  if ssh_hub test -e /etc/nixod/config; then hub_installed=1; else hub_installed=0; fi
fi

if ! online; then mark 0 u
elif gh auth status >/dev/null 2>&1; then mark 0 1
else mark 0 0 "gh auth status fails"; fi

if [[ ! -e settings.nix ]] || grep -qE '= null;[[:space:]]*# NIXOD:FILL' settings.nix; then
  mark 1 0 "NIXOD:FILL left in settings.nix"
elif [[ -z $(git config user.name || true) ]]; then
  mark 1 0 "git config user.name is not set"
else mark 1 1; fi

if [[ -e hosts/$name/default.nix && -e hosts/$name/hardware-configuration.nix ]]; then mark 2 1
else mark 2 0 "hosts/$name/default.nix or hardware-configuration.nix missing"; fi

if ! in_network "$name"; then mark 3 0 "machines.$name is not in network.nix"
elif [[ ! -e $key ]]; then mark 3 0 "$key is missing"
else mark 3 1; fi

if [[ $hub_installed == 1 ]]; then mark 4 1 "the hub is installed"
elif ! online || [[ -z $address ]]; then mark 4 u "${address:+offline}${address:-no hub address in network.nix yet}"
elif ssh_hub true; then mark 4 1
else mark 4 0 "ssh -i $key -o BatchMode=yes root@$address fails"; fi

if [[ -e hosts/$hub/default.nix && -e hosts/$hub/disko.nix ]]; then mark 5 1
else mark 5 0 "hosts/$hub/default.nix or disko.nix missing"; fi

staged=1
for f in var/lib/syncthing/.config/syncthing/cert.pem etc/ssh/ssh_host_ed25519_key var/lib/nixod/deploy_key var/lib/nixod/console-password; do
  [[ -s $staging/$f ]] || staged=0
done
if ! in_network "$hub"; then mark 6 0 "machines.$hub is not in network.nix"
elif [[ $hub_installed == 1 ]]; then mark 6 1 "the hub is installed"
elif [[ $staged == 1 ]]; then mark 6 1
elif [[ $hub_installed == u ]]; then
  # The staging dir is deleted by the install: without the network, an
  # installed hub and lost keys look the same. Never suggest new keys then.
  mark 6 u "no staged identity: the hub may be installed already (check without --offline before making a new identity)"
else
  mark 6 0 "the staged identity in $staging is incomplete or gone: a new one is needed, and its public parts in network.nix (nixod doc init, Resuming)"
fi

if [[ -e hosts/$hub/hardware-configuration.nix ]]; then mark 7 1
else mark 7 0 "hosts/$hub/hardware-configuration.nix missing"; fi

if [[ -n $(git status --porcelain 2>/dev/null) ]]; then mark 8 0 "uncommitted changes"
elif ! online; then mark 8 u "offline"
elif ! git fetch --quiet origin "$branch" 2>/dev/null; then mark 8 0 "can't fetch origin/$branch"
elif ! git merge-base --is-ancestor HEAD "refs/remotes/origin/$branch" 2>/dev/null; then mark 8 0 "HEAD is not pushed to origin/$branch"
elif ! in_network "$hub"; then mark 8 0 "network.nix has no hub yet"
else mark 8 1; fi

case $hub_installed in
1) mark 9 1 ;;
0) mark 9 0 "the VPS doesn't run the hub yet" ;;
*) mark 9 u "${address:+offline}${address:-no hub address in network.nix yet}" ;;
esac

if [[ -e /etc/nixod/config ]]; then mark 10 1
else mark 10 0 "this machine doesn't run nixod yet"; fi

titles=(
  "GitHub login"
  "settings.nix and git identity"
  "this machine described (hosts/$name/)"
  "this machine's identity, in network.nix"
  "root SSH to the VPS with $key"
  "the hub described (hosts/$hub/)"
  "the hub's identity: in network.nix, staged"
  "the hub's hardware configuration"
  "checked, built, committed and pushed"
  "the hub installed"
  "this machine switched"
)

printf 'nixod init: %s, hub %s%s\n' "$name" "$hub" "${address:+ at $address}"
next=
unchecked=0
for i in "${!titles[@]}"; do
  case ${state[$i]} in
  1) box="[x]" ;;
  0) box="[ ]" ;;
  *) box="[?]" ;;
  esac
  printf '  %s %2d  %s%s\n' "$box" "$i" "${titles[$i]}" "${detail[$i]:+: ${detail[$i]}}"
  [[ -z $next && ${state[$i]} == u ]] && unchecked=1
  [[ -n $next || ${state[$i]} != 0 ]] || next=$i
done
note=
[[ $unchecked == 1 ]] && note=" Steps marked ? before it weren't checked."
if [[ -n $next ]]; then
  echo "Next: step $next (nixod doc init).$note"
elif [[ $unchecked == 1 ]]; then
  echo "Nothing left that could be checked; the steps marked ? weren't."
else
  echo "Init is done: finish with step 11 (nixod doc init)."
fi
