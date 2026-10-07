#!/usr/bin/env bash
# nixod doc [<name>]
#
# Prints one of the agent playbooks shipped with this version of nixod (or
# lists them). They are docs/agent/*.md in the framework repo.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

docs=$(dirname "${BASH_SOURCE[0]}")/../docs
name=${1:-}

case $name in
-h | --help)
  echo "Usage: nixod doc [<name>]   (no name: list the playbooks)"
  ;;
"")
  for f in "$docs"/*.md; do
    printf '  %-16s %s\n' "$(basename "$f" .md)" "$(sed -n '1s/^# *//p' "$f")"
  done
  ;;
*)
  [[ -e $docs/$name.md ]] || die "no playbook '$name' (nixod doc lists them)"
  cat "$docs/$name.md"
  ;;
esac
