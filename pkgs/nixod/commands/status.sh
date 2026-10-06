#!/usr/bin/env bash
# nixod status   (any machine)
#
# The commit this machine runs vs the branch, the hub's last update, and
# which Syncthing peers are connected. Changes nothing (no fetch either).
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
load_config

[[ ${1:-} == -h || ${1:-} == --help ]] && {
  echo "Usage: nixod status"
  exit 0
}

if [[ ${NIXOD_ROLE:-} == hub ]]; then
  clone=$NIXOD_STATE/repo
  st_home=/var/lib/syncthing/.config/syncthing
else
  clone=$(expand_home "${NIXOD_REPO_PATH:-~/nixod}")
  st_home=$HOME/.config/syncthing
fi

printf 'machine:  %s (%s)\n' "${NIXOD_NAME:-?}" "${NIXOD_ROLE:-?}"
printf 'running:  %s\n' "$(running_rev || true)"
if [[ -d $clone/.git ]]; then
  printf '%-9s %s (last fetched)\n' "$NIXOD_BRANCH:" \
    "$(git -C "$clone" rev-parse --verify --quiet "refs/remotes/origin/$NIXOD_BRANCH" || echo '?')"
fi
if [[ ${NIXOD_ROLE:-} == hub ]]; then
  printf 'update:   %s\n' "$(cat "$NIXOD_STATE/status" 2>/dev/null || echo 'never ran')"
fi

# Syncthing peers, from its local API (needs read access to its config).
if [[ -r $st_home/config.xml ]]; then
  apikey=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$st_home/config.xml")
  api() { curl -sf -H "X-API-Key: $apikey" "http://127.0.0.1:8384$1"; }
  if names=$(api /rest/config/devices) && conns=$(api /rest/system/connections); then
    echo "syncthing peers:"
    jq -r --argjson c "$conns" \
      '.[] | select(.deviceID as $id | $c.connections | has($id)) |
       "  \(.name): \(if $c.connections[.deviceID].connected then "connected" else "not connected" end)"' \
      <<<"$names"
  fi
fi
