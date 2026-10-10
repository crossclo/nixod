#!/usr/bin/env bash
# nixod review <pr number | branch>   (on a trusted host, in its clone)
#
# Shows what a join request changes, without touching the working tree:
# the machines it adds (or removes) and the folders each new one gets, the
# network.nix diff, and, loudly, any change to other machines' entries or to
# folder options in network.nix, and any file outside network.nix and the
# new host's hosts/<name>/ (a join request has no reason to change what
# other machines run). Then builds the new
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

network_at() { # network_at <commit>: its network.nix, as JSON
  local f
  f=$(mktemp)
  git show "$1:network.nix" >"$f"
  nix_ eval --json --file "$f"
  rm -f "$f"
}
net_before=$(network_at "$fork")
net_after=$(network_at "$head")
before=$(jq -r '.machines | keys[]' <<<"$net_before" | sort)
after=$(jq -r '.machines | keys[]' <<<"$net_after" | sort)
mapfile -t added < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)
mapfile -t removed < <(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)

step "Machines"
for m in "${added[@]}"; do
  info "+ $m (new), gets these folders:"
  jq -r --arg m "$m" '.machines[$m].folders // {} | to_entries[] | "      \(.key) at \(.value)"' <<<"$net_after" >&2
done
for m in "${removed[@]}"; do info "- $m (REMOVED by this request)"; done
[[ ${#added[@]} -gt 0 ]] || warn "this request adds no machine"

# Entries that exist on both sides and changed, and changed folder options:
# they change what other machines run or share.
mapfile -t changed < <(jq -rn --argjson a "$net_before" --argjson b "$net_after" '
  ($a.folders // {}) as $fa | ($b.folders // {}) as $fb
  | ($a.machines | keys[] | select($b.machines[.] != null and $a.machines[.] != $b.machines[.]) | "machines.\(.)"),
    ($fa | keys[] | select($fa[.] != $fb[.]) | "folders.\(.)")')
if [[ ${#changed[@]} -gt 0 ]]; then
  step "WARNING: this request changes existing entries in network.nix"
  warn "a join request only adds its own machine (and new folders); these change what others run or share:"
  printf '      %s\n' "${changed[@]}" >&2
fi

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
