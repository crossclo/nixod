# The playbooks and AGENTS.md only mention what exists: every `nixod <cmd>`
# is a command, every flag after it is one that command takes, every
# `nixod doc <name>` and playbook in AGENTS.md's table is a playbook. Every
# command answers --help; `nixod doc` lists and prints the playbooks.
{ self, pkgs }:

let
  nixod = self.packages.${pkgs.stdenv.hostPlatform.system}.nixod;
in
pkgs.runCommand "nixod-docs" { nativeBuildInputs = [ nixod ]; } ''
  set -euo pipefail
  commands=${nixod}/libexec/nixod/commands
  docs=${nixod}/libexec/nixod/docs
  texts="$docs/*.md ${../template/AGENTS.md}"
  fail() { echo "$*"; exit 1; }

  # Every command answers --help.
  for c in $commands/*.sh; do
    nixod "$(basename "$c" .sh)" --help >/dev/null 2>&1 || fail "nixod $(basename "$c" .sh) --help failed"
  done

  # `nixod <cmd> ...flags` in code (inline spans, code-block lines): the
  # command exists and takes the flags.
  { grep -ohE '`(! )?(nix run \.#nixod --|nixod) [a-z-]+[^`]*`' $texts | tr -d '`' | sed -E 's/^(! )?nix run \.#nixod --/nixod/'
    grep -hE '^ *nixod [a-z-]+' $texts
  } | while read -r _ cmd rest; do
    [ -e "$commands/$cmd.sh" ] || fail "unknown command in the docs: nixod $cmd"
    rest=''${rest%% -- *}   # flags after ' -- ' belong to another tool
    for flag in $(grep -oE -- '--[a-z][a-z-]*' <<<"$rest" || true); do
      grep -qF -- "$flag" "$commands/$cmd.sh" || fail "nixod $cmd has no $flag (docs)"
    done
  done

  # `nixod doc <name>` and AGENTS.md's playbook column name real playbooks.
  for name in $(grep -ohE 'nixod doc [a-z-]+' $texts | cut -d' ' -f3) \
    $(grep -oE '^\| [^|]+ \| `[a-z-]+`' ${../template/AGENTS.md} | grep -oE '`[a-z-]+`$' | tr -d '`'); do
    [ -e "$docs/$name.md" ] || fail "no playbook '$name'"
  done

  # `nixod doc` lists them all; `nixod doc init` prints one.
  listing=$(nixod doc)
  for f in $docs/*.md; do
    grep -q "^  $(basename "$f" .md) " <<<"$listing" || fail "nixod doc doesn't list $(basename "$f")"
  done
  [ "$(nixod doc init | head -1)" = "# init: set up the network (first host + hub)" ] || fail "nixod doc init"

  touch $out
''
