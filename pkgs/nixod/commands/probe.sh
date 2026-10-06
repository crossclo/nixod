#!/usr/bin/env bash
# nixod probe <user@ip> [-- <ssh options>]   (on the first host)
#
# Reads the VPS's stock system over SSH, without changing anything, and
# prints JSON: boot mode (bios/uefi), interfaces with their addresses
# ("dynamic": true means DHCP), routes, DNS servers, disks (and their
# /dev/disk/by-id names), virtualization and the storage/network kernel
# modules in use. The agent writes hosts/<hub>/ (network, disko.nix, boot
# loader) from it.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

usage() {
  cat <<'EOF'
Usage: nixod probe <user@ip> [--dry-run] [-- <ssh options>]
EOF
}

target=
ssh_opts=()
while [[ $# -gt 0 ]]; do
  case $1 in
  --dry-run) DRY_RUN=1 ;;
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

step "Reading the stock system on $target (read-only)"
if [[ $DRY_RUN == 1 ]]; then
  run ssh "${ssh_opts[@]}" "$target" sh -s "<" "$remote"
  exit 0
fi
ssh "${ssh_opts[@]}" "$target" sh -s <"$remote" | jq .
