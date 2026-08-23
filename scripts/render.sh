#!/bin/sh
# Render ONE candidate against ONE fixture, and show everything the harness
# would judge it on.
#
#   sh scripts/render.sh candidates/default.sh fixtures/first-render.json
#
# Claude Code captures the script's output instead of connecting it to the
# terminal, so a candidate cannot read the terminal width with `tput cols`; it
# reads COLUMNS and LINES, which Claude Code sets before running it. This
# harness sets them too — otherwise a candidate that sizes its output is being
# tested in conditions the real caller never provides. Override them to see how
# a candidate behaves on a narrow terminal:
#
#   COLUMNS=48 sh scripts/render.sh candidates/default.sh fixtures/steady.json
set -u

cand=${1:-}
fix=${2:-}
if [ -z "$cand" ] || [ -z "$fix" ]; then
	echo "usage: sh scripts/render.sh <candidate> <fixture>" >&2
	exit 2
fi
[ -f "$cand" ] || { echo "render: no such candidate: $cand" >&2; exit 2; }
[ -f "$fix" ] || { echo "render: no such fixture: $fix" >&2; exit 2; }

err=$(mktemp "${TMPDIR:-/tmp}/statusline-err.XXXXXX") || exit 2
out=$(mktemp "${TMPDIR:-/tmp}/statusline-out.XXXXXX") || exit 2
trap 'rm -f "$err" "$out"' EXIT

COLUMNS=${COLUMNS:-100} LINES=${LINES:-30} export COLUMNS LINES
sh "$cand" <"$fix" >"$out" 2>"$err"
rc=$?

echo "candidate: $cand"
echo "fixture:   $fix   (COLUMNS=$COLUMNS)"
echo "exit:      $rc"
echo "--- stdout, as the status line would show it ---"
cat "$out"
echo "--- end ---"
if [ -s "$err" ]; then
	echo "STDERR (a status line that writes here is misconfigured, not styled):"
	sed 's/^/  /' "$err"
fi
exit "$rc"
