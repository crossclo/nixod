#!/usr/bin/env bash
# nixod probe <user@ip> [-- <ssh options>]   (on the first host)
#
# Reads the VPS's stock system over SSH, without changing anything, and
# prints JSON: boot mode (bios/uefi), interfaces with their addresses
# ("dynamic": true: DHCP for IPv4, router advertisements for IPv6), routes,
# DNS servers, disks (and their /dev/disk/by-id names), memory, CPU
# architecture, virtualization and the storage/network kernel modules in use. The agent writes hosts/<hub>/ (network, disko.nix, boot
# loader) from it.
# It logs in with this machine's nixod key, without prompting (BatchMode):
# the user accepts the VPS's host key and authorizes the key beforehand.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

usage() {
  cat <<'EOF'
Usage: nixod probe <user@ip> [--key PATH] [--dry-run] [-- <ssh options>]

  --key PATH   SSH key that logs into the VPS (default ~/.ssh/nixod_ed25519,
               when it exists)
EOF
}

target=
key=$HOME/.ssh/nixod_ed25519
ssh_opts=()
while [[ $# -gt 0 ]]; do
  case $1 in
  --dry-run) DRY_RUN=1 ;;
  --key) key=$2 && shift ;;
  -h | --help) usage && exit 0 ;;
  --)
    shift
    ssh_opts=("$@")
    break
    ;;
  -*) die "unknown option: $1" ;;
  *)
    [[ -z $target ]] || die "unexpected argument: $1"
    target=$1
    ;;
  esac
  shift
done
[[ -n $target ]] || {
  usage >&2
  exit 2
}

remote=$(dirname "${BASH_SOURCE[0]}")/../probe-remote.sh
ssh_opts=(-o BatchMode=yes "${ssh_opts[@]}")
[[ -e $key ]] && ssh_opts=(-i "$key" "${ssh_opts[@]}")

step "Reading the stock system on $target (read-only)"
if [[ $DRY_RUN == 1 ]]; then
  run ssh "${ssh_opts[@]}" "$target" sh -s "<" "$remote"
  exit 0
fi
ssh "${ssh_opts[@]}" "$target" sh -s <"$remote" | jq .
