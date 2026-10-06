#!/usr/bin/env bash
# nixod review <pr number | branch>   (on a trusted host, in its clone)
#
# Shows what a join request changes, without touching the working tree:
# the machines it adds (or removes), the network.nix diff, and, loudly, any
# file outside network.nix and the new host's hosts/<name>/ (a join request
# has no reason to change what other machines run). Then builds the new
# host and the hub, and records the reviewed commit: `nixod approve` merges
# exactly that commit, nothing pushed after it.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

usage() {
  cat <<'EOF'
Usage: nixod review <pr number | branch> [--no-build]
EOF
}

id=
build=1
while [[ $# -gt 0 ]]; do
  case $1 in
  --no-build) build=0 ;;
  -h | --help) usage && exit 0 ;;
  -*) die "unknown option: $1" ;;
  *)
    [[ -z $id ]] || die "unexpected argument: $1"
    id=$1
    ;;
  esac
  shift
done
[[ -n $id ]] || {
  usage >&2
  exit 2
}
cd "$(git rev-parse --show-toplevel)"

step "Fetch the request and $NIXOD_BRANCH"
head=$(fetch_request "$id")
base=refs/remotes/origin/$NIXOD_BRANCH
fork=$(git merge-base "$base" "$head") || die "the request has no history in common with $NIXOD_BRANCH"
info "request: $head"

machines_at() { # machines_at <commit>: machine names in its network.nix
  local f
  f=$(mktemp)
  git show "$1:network.nix" >"$f"
  nix_ eval --json --file "$f" machines --apply builtins.attrNames | jq -r '.[]'
  rm -f "$f"
}
before=$(machines_at "$fork" | sort)
after=$(machines_at "$head" | sort)
mapfile -t added < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)
mapfile -t removed < <(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)

step "Machines"
for m in "${added[@]}"; do info "+ $m (new)"; done
for m in "${removed[@]}"; do info "- $m (REMOVED by this request)"; done
[[ ${#added[@]} -gt 0 ]] || warn "this request adds no machine"

step "Files"
git --no-pager diff --stat "$fork" "$head" >&2

step "network.nix"
git --no-pager diff "$fork" "$head" -- network.nix >&2

# Everything that is neither network.nix nor a new host's own directory.
own=(":(exclude)network.nix")
for m in "${added[@]}"; do own+=(":(exclude)hosts/$m"); done
mapfile -t shared < <(git diff --name-only "$fork" "$head" -- . "${own[@]}")
if [[ ${#shared[@]} -gt 0 ]]; then
  step "WARNING: this request also changes shared files"
  warn "a join request has no reason to change these; they affect other machines:"
  printf '      %s\n' "${shared[@]}" >&2
  git --no-pager diff "$fork" "$head" -- . "${own[@]}" >&2
fi

if [[ $build == 1 ]]; then
  step "Build the new machines and the hub"
  tree=$(mktemp -d)
  git worktree add --quiet --detach "$tree/repo" "$head"
  trap 'git worktree remove --force "$tree/repo"; rm -rf "$tree"' EXIT
  # shellcheck disable=SC2016 # a Nix expression, not shell
  hub=$(nix_ eval --raw --file "$tree/repo/network.nix" machines \
    --apply 'ms: builtins.head (builtins.filter (n: ms.${n}.role == "hub") (builtins.attrNames ms))')
  for m in "${added[@]}" "$hub"; do
    info "building $m"
    nix_ build --no-link "$tree/repo#nixosConfigurations.$m.config.system.build.toplevel"
  done
fi

printf '%s\n' "$head" >"$(review_marker "$id")"
step "Reviewed $head"
info "To accept it: nixod approve $id"
