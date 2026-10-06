#!/usr/bin/env bash
# nixod install-hub <name> <user@ip> --stage hardware|install   (first host)
#
# Installs NixOS on the hub with nixos-anywhere, in two stages:
#   hardware: boots the NixOS installer in the VPS's RAM (kexec; the disk is
#             not touched, the provider's OS comes back at the next reboot)
#             and writes hosts/<name>/hardware-configuration.nix.
#   install:  checks the staged identity matches network.nix, adds the deploy
#             key on GitHub, builds the hub, WIPES THE DISK (disko), installs
#             with the staged identity, reboots, then deletes the staging dir.
# Extra nixos-anywhere flags go after `--` (they come last, so they win).
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

usage() {
  cat <<'EOF'
Usage: nixod install-hub <name> <user@ip> --stage hardware|install [options]
                         [-- <extra nixos-anywhere flags>]

  --staging DIR        the hub's identity (default $XDG_RUNTIME_DIR/nixod/hub-<name>)
  --flake DIR          the instance repo (default .)
  --store-paths D S    already built disko script and system: skip the build
  --no-deploy-key      don't add the deploy key on GitHub
  --yes                the user already confirmed (kexec / wiping the disk)
  --dry-run            print the steps and commands, run nothing
EOF
}

name=
target=
stage=
staging=
flake=.
disko_script=
system=
deploy_key_on_github=1
extra=()
while [[ $# -gt 0 ]]; do
  case $1 in
  --stage) stage=$2 && shift ;;
  --staging) staging=$2 && shift ;;
  --flake) flake=$2 && shift ;;
  --store-paths) disko_script=$2 && system=$3 && shift 2 ;;
  --no-deploy-key) deploy_key_on_github=0 ;;
  --yes) YES=1 ;;
  --dry-run) DRY_RUN=1 ;;
  -h | --help) usage && exit 0 ;;
  --)
    shift
    extra=("$@")
    break
    ;;
  -*) die "unknown option: $1" ;;
  *)
    if [[ -z $name ]]; then
      name=$1
    elif [[ -z $target ]]; then
      target=$1
    else
      die "unexpected argument: $1"
    fi
    ;;
  esac
  shift
done
[[ -n $name && -n $target && ($stage == hardware || $stage == install) ]] || {
  usage >&2
  exit 2
}
staging=$(realpath -m "${staging:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nixod/hub-$name}")
cd "$flake"

stage_hardware() {
  local hw=hosts/$name/hardware-configuration.nix

  confirm "This replaces the OS running on $target with the NixOS installer, in RAM only (the disk is not touched; a reboot brings the provider's OS back)." "$name"

  step "Boot the NixOS installer on $target (kexec) and generate $hw"
  run nixos-anywhere \
    --flake ".#$name" \
    --phases kexec \
    --generate-hardware-config nixos-generate-config "$hw" \
    "${extra[@]}" \
    "$target"

  step "Next"
  info "Review $hw, build both machines, commit (signed) and push, then:"
  info "nixod install-hub $name $target --stage install"
}

stage_install() {
  local st=$staging/var/lib/syncthing/.config/syncthing
  local deploy_pub=$staging/var/lib/nixod/deploy_key.pub
  local staged expected out

  step "Check the staged identity ($staging)"
  for f in "$st/cert.pem" "$st/key.pem" "$staging/etc/ssh/ssh_host_ed25519_key" "$staging/var/lib/nixod/deploy_key"; do
    [[ -e $f || $DRY_RUN == 1 ]] || die "missing $f: run 'nixod identity hub $name' first (with the same --staging)"
  done
  if [[ $DRY_RUN == 0 && -e network.nix ]]; then
    staged=$(syncthing_id "$st")
    expected=$(nix_ eval --raw --file network.nix "machines.$name.syncthingId")
    [[ $staged == "$expected" ]] ||
      die "the staged Syncthing ID ($staged) is not machines.$name.syncthingId in network.nix ($expected)"
    info "Syncthing ID matches network.nix: $staged"
  fi

  step "Check the repo is committed (the hub runs a clean commit)"
  if [[ $DRY_RUN == 0 ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --quiet HEAD -- || die "uncommitted changes: commit (signed) and push first"
  fi

  if [[ -z $system ]]; then
    step "Build the hub"
    if [[ $DRY_RUN == 1 ]]; then
      run nix_ build --no-link --print-out-paths ".#nixosConfigurations.$name.config.system.build.diskoScript" ".#nixosConfigurations.$name.config.system.build.toplevel"
      disko_script="<disko-script>" system="<system>"
    else
      out=$(nix_ build --no-link --print-out-paths \
        ".#nixosConfigurations.$name.config.system.build.diskoScript" \
        ".#nixosConfigurations.$name.config.system.build.toplevel")
      disko_script=$(sed -n 1p <<<"$out")
      system=$(sed -n 2p <<<"$out")
    fi
  fi

  confirm "This WIPES THE DISK of $target and installs the hub $name. Never do this to a hub that holds data." "$name"

  # The tree is copied as is onto the hub's root: make the modes right
  # whatever copied it here.
  step "Fix the staged files' permissions"
  run find "$staging" -type d -exec chmod 755 {} +
  run chmod 700 "$staging/var/lib/syncthing" "$staging/var/lib/syncthing/.config/syncthing" "$staging/var/lib/nixod"
  run chmod 600 "$st/key.pem" "$staging/etc/ssh/ssh_host_ed25519_key" "$staging/var/lib/nixod/deploy_key"
  run chmod 644 "$st/cert.pem" "$staging/etc/ssh/ssh_host_ed25519_key.pub" "$deploy_pub"

  if [[ $deploy_key_on_github == 1 ]]; then
    step "Add the deploy key on GitHub (read-only)"
    if [[ $DRY_RUN == 0 ]] && gh repo deploy-key list | grep -qF "$(cut -d' ' -f2 "$deploy_pub")"; then
      info "already there"
    else
      run gh repo deploy-key add "$deploy_pub" --title "nixod hub $name"
    fi
  fi

  step "Install (disko wipes the disk, then nixos-install, then reboot)"
  # 237 is the syncthing user/group on NixOS (ids.uids.syncthing).
  run nixos-anywhere \
    --store-paths "$disko_script" "$system" \
    --extra-files "$staging" \
    --chown /var/lib/syncthing 237:237 \
    --phases kexec,disko,install,reboot \
    "${extra[@]}" \
    "$target"

  step "Delete the staging dir (the hub's private keys now live only on the hub)"
  run rm -rf "$staging"
}

"stage_$stage"
