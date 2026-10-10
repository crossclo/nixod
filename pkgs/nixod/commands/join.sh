#!/usr/bin/env bash
# nixod join [<name>]   (on the new host, in the clone of the repo)
#
# Sends the join request: the new host's entry in network.nix and its
# hosts/<name>/ go on a branch join/<name>, which is pushed, and a pull
# request is opened. A trusted machine reviews and approves it
# (`nixod review`, `nixod approve`).
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

usage() {
  cat <<'EOF'
Usage: nixod join [<name>] [--no-build] [--no-pr] [--dry-run]

  <name>       this machine in network.nix (default: the host name)
  --no-build   don't build this machine first
  --no-pr      push the branch only (no GitHub pull request)
EOF
}

name=
build=1
pr=1
while [[ $# -gt 0 ]]; do
  case $1 in
  --no-build) build=0 ;;
  --no-pr) pr=0 ;;
  --dry-run) DRY_RUN=1 ;;
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
branch=join/$name
cd "$(git rev-parse --show-toplevel)"

step "Check $name is described"
role=$(nix_ eval --raw --file network.nix "machines.$name.role" 2>/dev/null) ||
  die "machines.$name is not in network.nix: add its entry (nixod identity host $name prints it)"
[[ $role == host ]] || die "machines.$name is a $role: only hosts join"
for f in default.nix hardware-configuration.nix; do
  [[ -e hosts/$name/$f ]] || die "hosts/$name/$f is missing"
done

step "Check the clone is where settings.repo.path says"
# Update checks and `nixod update` look for the clone there.
# shellcheck disable=SC2088 # a literal ~, expanded by expand_home below
want=$(nix_ eval --raw --file settings.nix repo.path 2>/dev/null) || want='~/nixod'
[[ $(realpath -m "$(expand_home "$want")") == "$(realpath -m "$PWD")" ]] ||
  die "this clone is at $PWD, but settings.repo.path is $want: move the clone there (every machine keeps it at the same place)"

step "Branch $branch"
if git show-ref --verify --quiet "refs/heads/$branch"; then
  run git switch --quiet "$branch"
else
  run git switch --quiet --create "$branch"
fi
# Flakes only see files git knows about.
run git add -- network.nix "hosts/$name"

if [[ $build == 1 ]]; then
  step "Build $name"
  run nix_ build --no-link ".#nixosConfigurations.$name.config.system.build.toplevel"
fi

step "Commit"
if [[ $DRY_RUN == 0 ]] && git diff --cached --quiet; then
  info "nothing new to commit"
else
  run git commit --quiet -m "nixod: join $name"
fi

step "Push $branch"
run git push --quiet --set-upstream origin "$branch"

if [[ $pr == 1 ]]; then
  step "Open the join request (pull request)"
  run gh pr create --base "$NIXOD_BRANCH" --head "$branch" --title "nixod: join $name" --body "New host \`$name\` asks to join the network.

On a trusted machine: \`nixod review <this PR's number>\`, then \`nixod approve <number>\`.
The hub applies the approved merge on its own; then rebuild \`$name\`."
fi

step "Next"
info "On a trusted machine: nixod review <PR number or $branch>, then nixod approve."
