#!/usr/bin/env bash
# NDA guard: fail if any term from a PRIVATE denylist appears in the repo.
# The denylist lives outside the repo on purpose: the list itself is sensitive.
#   NDA_DENYLIST   path to the denylist (default: ~/.config/nda-denylist.txt)
#   --staged       scan only staged content (used by the pre-commit hook)
#   --history      also scan every commit in git history
set -euo pipefail
DENYLIST="${NDA_DENYLIST:-$HOME/.config/nda-denylist.txt}"
MODE="${1:-tree}"

if [[ ! -f "$DENYLIST" ]]; then
  echo "nda-scan: no denylist at $DENYLIST - skipping (create one to enable the guard)" >&2
  exit 0
fi

patterns="$(mktemp)"; trap 'rm -f "$patterns"' EXIT
grep -vE '^\s*(#|$)' "$DENYLIST" > "$patterns"

hits=0
case "$MODE" in
  --staged)
    if git diff --cached --name-only -z --diff-filter=ACMR | xargs -0 -r git grep --cached -n -I -i -E -f "$patterns" -- ; then hits=1; fi ;;
  --history)
    if git grep -n -I -i -E -f "$patterns" -- . ; then hits=1; fi
    for c in $(git rev-list --all); do
      if git grep -n -I -i -E -f "$patterns" "$c" -- ; then hits=1; fi
    done
    if git log --all --format='%an %ae %s %b' | grep -i -E -f "$patterns"; then hits=1; fi ;;
  *)
    # Everything git would publish: tracked plus untracked-but-not-ignored files.
    # Ignored paths (.kube/, caches, state) never leave the machine, so they are not scanned.
    if git ls-files -co --exclude-standard -z | xargs -0 -r grep -nIiE -f "$patterns" -- ; then hits=1; fi ;;
esac

if [[ $hits -ne 0 ]]; then
  echo "nda-scan: FAILED - denylisted term found (see lines above)" >&2
  exit 1
fi
echo "nda-scan: clean ($MODE)"
