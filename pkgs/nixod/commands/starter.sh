#!/usr/bin/env bash
# nixod starter [list] | copy <file>... | diff [<file>...]   (in the instance repo)
#
# starter/ is a set of plain config files shipped with nixod: an i3 desktop,
# zsh, Neovim, kitty... Nothing in nixod imports them. `copy` puts files into
# this repo (home/<file>, system/<file>), where they are the user's own from
# then on: nixod never changes them again. A file's `# needs:` line names the
# files it relies on (its colors, its fonts...); they are copied with it.
# `diff` compares this repo's copies with this version's starter, to pull
# improvements in by hand.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

starter=$(dirname "${BASH_SOURCE[0]}")/../starter

usage() {
  cat <<'EOF'
Usage: nixod starter [list]             the starter files, and what each one is
       nixod starter copy <file>...     copy them (and what they need) into this repo
       nixod starter diff [<file>...]   this repo's copies against this version's starter
Run it in the instance repo. <file> is a path as listed, e.g. home/i3.nix.
EOF
}

files() { (cd "$starter" && find home system -name '*.nix' | sort); }
needs() { sed -n 's/^# needs: //p' "$starter/$1" | tr ' ' '\n' | sed '/^$/d'; }
# A data file (the palette) is imported by the files that use it, not listed
# in imports.
is_module() { ! grep -q '^# Not a module' "$starter/$1"; }

in_instance() {
  [[ -e settings.nix && -e network.nix ]] || die "run this in the instance repo (no settings.nix or network.nix here)"
}

known() { [[ $1 != *..* && -f $starter/$1 ]] || die "no starter file '$1' (nixod starter lists them)"; }

cmd=${1:-list}
[[ $# -gt 0 ]] && shift
case $cmd in
-h | --help)
  usage
  ;;

list)
  for f in $(files); do
    printf '  %-24s %s\n' "$f" "$(sed -n '1s/^# *//p' "$starter/$f")"
  done
  ;;

copy)
  [[ $# -gt 0 ]] || die "copy what? (nixod starter lists the files)"
  in_instance
  # The files asked for, then what they need, each once.
  declare -A seen=()
  queue=("$@")
  todo=()
  while [[ ${#queue[@]} -gt 0 ]]; do
    f=${queue[0]}
    queue=("${queue[@]:1}")
    [[ -z ${seen[$f]:-} ]] || continue
    seen[$f]=1
    known "$f"
    todo+=("$f")
    mapfile -t -O "${#queue[@]}" queue < <(needs "$f")
  done

  step "Copy into $(pwd)"
  copied=()
  for f in "${todo[@]}"; do
    if [[ -e $f ]]; then
      info "$f is already here, kept (nixod starter diff $f)"
      continue
    fi
    install -D -m 644 "$starter/$f" "$f"
    info "$f"
    copied+=("$f")
  done
  [[ ${#copied[@]} -gt 0 ]] || exit 0

  step "Import them"
  for dir in home system; do
    imports=$(for f in "${copied[@]}"; do
      [[ $f == "$dir"/* ]] && is_module "$f" && printf ' ./%s' "${f#"$dir"/}"
    done || true)
    [[ -z $imports ]] || info "$dir/default.nix: imports = [$imports ];"
  done
  info "They are this repo's files now: edit them freely."
  ;;

diff)
  in_instance
  [[ $# -gt 0 ]] || mapfile -t argv < <(files)
  [[ $# -eq 0 ]] || argv=("$@")
  rc=0
  for f in "${argv[@]}"; do
    known "$f"
    [[ -e $f ]] || continue
    diff -u --label "starter/$f" --label "$f" "$starter/$f" "$f" || rc=1
  done
  exit $rc
  ;;

*)
  usage >&2
  exit 2
  ;;
esac
