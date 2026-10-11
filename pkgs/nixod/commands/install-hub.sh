#!/usr/bin/env bash
# nixod install-hub <name> <user@ip> --stage hardware|install   (first host)
#
# Installs NixOS on the hub with nixos-anywhere, in two stages:
#   hardware: boots the NixOS installer in the VPS's RAM (kexec; the disk is
#             not touched, the provider's OS comes back at the next reboot)
#             and writes hosts/<name>/hardware-configuration.nix.
#   install:  checks the staged identity matches network.nix (Syncthing ID,
#             SSH host key, deploy key) and the console password is staged,
#             adds the deploy key on GitHub, builds the hub, WIPES THE DISK
#             (disko), installs with the staged identity, reboots, puts the
#             hub's host key in ~/.ssh/known_hosts in place of the provider
#             OS's, and deletes the staging dir.
# Extra nixos-anywhere flags go after `--` (they come last, so they win).
#
# Host key: nixos-anywhere turns host key checking off. install-hub runs it
# with the VPS's host key pinned instead: the key the user checked (init
# step 4) must be in ~/.ssh/known_hosts, and every SSH connection must
# present it. The kexec installer keeps the provider OS's host keys, so the
# same key holds before and after the kexec.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

usage() {
  cat <<'EOF'
Usage: nixod install-hub <name> <user@ip> --stage hardware|install [options]
                         [-- <extra nixos-anywhere flags>]

  --staging DIR        the hub's identity (default $XDG_RUNTIME_DIR/nixod/hub-<name>)
  --key PATH           SSH key that logs into the VPS as root (default
                       ~/.ssh/nixod_ed25519, when it exists)
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
key=$HOME/.ssh/nixod_ed25519
flake=.
disko_script=
system=
deploy_key_on_github=1
extra=()
while [[ $# -gt 0 ]]; do
  case $1 in
  --stage) stage=$2 && shift ;;
  --staging) staging=$2 && shift ;;
  --key) key=$2 && shift ;;
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
# nixos-anywhere logs in with this machine's nixod key (the user authorized it
# on the VPS); without it, ssh's defaults and agent.
key_opts=()
[[ -e $key ]] && key_opts=(-i "$key")

# pin_host_key: puts an `ssh` first on PATH that checks the VPS's host key
# against the one in ~/.ssh/known_hosts. ssh keeps the first value given for
# an option, so these come before nixos-anywhere's own (which turn checking
# off). nix copy and ssh-copy-id run that same `ssh`.
pin_host_key() {
  local host=${target#*@} real dir
  step "Pin the VPS's host key ($host, from ~/.ssh/known_hosts)"
  if [[ $DRY_RUN == 1 ]]; then
    info "ssh -o StrictHostKeyChecking=yes -o UserKnownHostsFile=<$host's entries> ..."
    return
  fi
  dir=$(mktemp -d)
  # shellcheck disable=SC2064 # expand now: the path is known
  trap "rm -rf '$dir'" EXIT
  ssh-keygen -F "$host" 2>/dev/null | grep -v '^#' >"$dir/known_hosts" || true
  [[ -s $dir/known_hosts ]] ||
    die "$host's host key isn't in ~/.ssh/known_hosts. The user connects once (ssh root@$host), compares the fingerprint with the provider's panel or console, and accepts it (nixod doc init, step 4)."
  real=$(command -v ssh)
  cat >"$dir/ssh" <<EOF
#!/bin/sh
exec $real -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$dir/known_hosts -o GlobalKnownHostsFile=/dev/null "\$@"
EOF
  chmod +x "$dir/ssh"
  PATH=$dir:$PATH
  info "$(ssh-keygen -lf "$dir/known_hosts" | head -1)"
  # nixos-anywhere retries a failing first connection forever: try it here.
  ssh -o BatchMode=yes -o ConnectTimeout=15 "${key_opts[@]}" "$target" true ||
    die "can't log into $target with the checked host key and this machine's key. If the host key changed, find out why before going on (it should only change when the OS is reinstalled)."
}

stage_hardware() {
  local hw=hosts/$name/hardware-configuration.nix

  confirm "This replaces the OS running on $target with the NixOS installer, in RAM only (the disk is not touched; a reboot brings the provider's OS back)." "$name"

  pin_host_key

  step "Boot the NixOS installer on $target (kexec) and generate $hw"
  run nixos-anywhere \
    "${key_opts[@]}" \
    --flake ".#$name" \
    --phases kexec \
    --generate-hardware-config nixos-generate-config "$hw" \
    "${extra[@]}" \
    "$target"
  # The flake only sees files git knows about.
  run git add -- "$hw"

  step "Next"
  info "Review $hw, build both machines, commit (signed) and push, then:"
  info "nixod install-hub $name $target --stage install"
}

stage_install() {
  local st=$staging/var/lib/syncthing/.config/syncthing
  local deploy_pub=$staging/var/lib/nixod/deploy_key.pub
  local password=$staging/var/lib/nixod/console-password
  local staged expected out owner field

  step "Check the staged identity ($staging)"
  for f in "$st/cert.pem" "$st/key.pem" "$staging/etc/ssh/ssh_host_ed25519_key" "$staging/var/lib/nixod/deploy_key"; do
    [[ -e $f || $DRY_RUN == 1 ]] || die "missing $f. The staged identity is gone (it lives in RAM: a logout or a reboot deletes it).
Make a new one and publish it before installing:
  1. nixod identity hub $name                      (new keys; same --staging if you used one)
  2. the user, in a terminal: nixod identity hub $name --console-password
  3. put the printed syncthingId, sshHostKey and deployKey in machines.$name in network.nix
  4. build, commit (signed) and push
  5. run this again"
  done
  [[ -s $password || $DRY_RUN == 1 ]] ||
    die "no console password staged: the user runs, in a terminal: nixod identity hub $name --console-password"
  if [[ $DRY_RUN == 0 && -e network.nix ]]; then
    staged=$(syncthing_id "$st")
    expected=$(nix_ eval --raw --file network.nix "machines.$name.syncthingId")
    [[ $staged == "$expected" ]] ||
      die "the staged Syncthing ID ($staged) is not machines.$name.syncthingId in network.nix ($expected)"
    for field in sshHostKey:etc/ssh/ssh_host_ed25519_key.pub deployKey:var/lib/nixod/deploy_key.pub; do
      staged=$(cut -d' ' -f1,2 "$staging/${field#*:}")
      expected=$(nix_ eval --raw --file network.nix "machines.$name.${field%%:*}" | cut -d' ' -f1,2)
      [[ $staged == "$expected" ]] ||
        die "the staged ${field%%:*} is not machines.$name.${field%%:*} in network.nix: the staged identity and network.nix don't match"
    done
    info "Syncthing ID, SSH host key and deploy key match network.nix"
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
  run chmod 600 "$st/key.pem" "$staging/etc/ssh/ssh_host_ed25519_key" "$staging/var/lib/nixod/deploy_key" "$password"
  run chmod 644 "$st/cert.pem" "$staging/etc/ssh/ssh_host_ed25519_key.pub" "$deploy_pub"

  if [[ $deploy_key_on_github == 1 ]]; then
    step "Add the deploy key on GitHub (read-only)"
    if [[ $DRY_RUN == 0 ]] && gh repo deploy-key list | grep -qF "$(cut -d' ' -f2 "$deploy_pub")"; then
      info "already there"
    else
      run gh repo deploy-key add "$deploy_pub" --title "nixod hub $name"
    fi
  fi

  step "The syncthing user and group on the hub (they own its identity)"
  if [[ $DRY_RUN == 1 ]]; then
    owner="<uid>:<gid>"
  else
    # shellcheck disable=SC2016 # Nix interpolation, not the shell's
    owner=$(nix_ eval --raw ".#nixosConfigurations.$name.config.users" \
      --apply 'u: "${toString u.users.syncthing.uid}:${toString u.groups.syncthing.gid}"' 2>/dev/null) || {
      # No flake to read it from (--store-paths): NixOS's fixed IDs.
      owner=237:237
      warn "can't read the syncthing user's IDs from .#nixosConfigurations.$name: using NixOS's fixed $owner"
    }
  fi
  info "$owner"

  pin_host_key

  step "Install (disko wipes the disk, then nixos-install, then reboot)"
  run nixos-anywhere \
    "${key_opts[@]}" \
    --store-paths "$disko_script" "$system" \
    --extra-files "$staging" \
    --chown /var/lib/syncthing "$owner" \
    --phases kexec,disko,install,reboot \
    "${extra[@]}" \
    "$target"

  step "Known hosts: ${target#*@} is the hub now (its key replaces the provider OS's)"
  if [[ $DRY_RUN == 1 ]]; then
    run ssh-keygen -R "${target#*@}"
    run echo "${target#*@} <hub host key>" ">>" "$HOME/.ssh/known_hosts"
  else
    ssh-keygen -R "${target#*@}" >/dev/null 2>&1 || true
    install -d -m 700 "$HOME/.ssh"
    printf '%s %s\n' "${target#*@}" "$(cut -d' ' -f1,2 "$staging/etc/ssh/ssh_host_ed25519_key.pub")" >>"$HOME/.ssh/known_hosts"
  fi

  step "Delete the staging dir (the hub's private keys now live only on the hub)"
  run rm -rf "$staging"
}

"stage_$stage"
