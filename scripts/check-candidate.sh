#!/bin/sh
# Run one candidate against EVERY fixture and judge it the way Claude Code
# does. Run it yourself for a quick answer; CI runs the same script on every
# candidate in the repo.
#
#   sh scripts/check-candidate.sh candidates/default.sh
#
# The candidate is executed DIRECTLY, so its own shebang decides the shell.
# `sh "$cand"` was the first draft and it lied in both directions: a bash
# candidate survived macOS /bin/sh (bash in POSIX mode) and then died under
# Ubuntu's dash in CI — a verdict about the referee's shell, not about the
# candidate as it declares itself.
#
# The failure modes are not invented here; they are what the published
# documentation says makes a status line go blank or show junk:
#
#   1. a non-zero exit                     — the status line goes blank
#   2. no output at all                    — the status line goes blank
#   3. anything on stderr                  — captured, and never displayed
#   4. the literal word null in stdout     — an absent or null field read
#                                            without a fallback, printed at the
#                                            user rather than handled
#   5. a line wider than COLUMNS           — truncated from the right with an
#                                            ellipsis, exactly the trap the
#                                            README describes; asserted at
#                                            several widths because a bar sized
#                                            for one terminal is not sized
#
# Mode 4 is matched as a standalone token, not a substring: a repository named
# null-safety is a correct bar, and a referee that fails it costs more than the
# defect it hunts. Mode 5 counts CHARACTERS with ANSI colour stripped — never
# bytes: a ten-cell block meter is thirty bytes and ten columns, so a
# byte-counting referee reds a 40-column bar a 47-column terminal displays whole.
set -u

cand=${1:-}
[ -n "$cand" ] || { echo "usage: sh scripts/check-candidate.sh <candidate>" >&2; exit 2; }
[ -f "$cand" ] || { echo "check-candidate: no such candidate: $cand" >&2; exit 2; }
[ -x "$cand" ] || {
	echo "check-candidate: $cand is not executable — chmod +x it so its own shebang decides the shell" >&2
	exit 2
}
case "$cand" in
*/*) run=$cand ;;
*) run=./$cand ;;
esac

fixtures=""
for f in fixtures/*.json; do
	[ -f "$f" ] && fixtures="$fixtures $f"
done
# Fail-closed, the direction every referee in this repo takes: an empty fixture
# set proves nothing about a candidate, so it is a refusal and not a pass.
[ -n "$fixtures" ] || { echo "check-candidate: no fixtures — nothing to referee" >&2; exit 2; }

# The widths the sweep asserts at. 100 is a laptop terminal, 80 the classic
# default, 40 a split pane — the narrow end is where every overflow this repo
# has observed actually lived.
widths="40 80 100"

# Character counting needs a UTF-8 locale or `wc -m` degrades to bytes and
# reds correct bars. Probe for one; without it the width check SKIPS, out
# loud, rather than asserting with a broken ruler.
charloc=""
for l in C.UTF-8 en_US.UTF-8; do
	if [ "$(printf '≡' | LC_ALL=$l wc -m 2>/dev/null | tr -d '[:space:]')" = 1 ]; then
		charloc=$l
		break
	fi
done
[ -n "$charloc" ] || echo "check-candidate: SKIP width checks — no UTF-8 locale answers wc -m"

esc=$(printf '\033')

err=$(mktemp "${TMPDIR:-/tmp}/statusline-cerr.XXXXXX") || exit 2
out=$(mktemp "${TMPDIR:-/tmp}/statusline-cout.XXXXXX") || exit 2
trap 'rm -f "$err" "$out"' EXIT

failed=0
for f in $fixtures; do
	for w in $widths; do
		COLUMNS=$w LINES=${LINES:-30} export COLUMNS LINES
		"$run" <"$f" >"$out" 2>"$err"
		rc=$?
		if [ "$rc" -ne 0 ]; then
			echo "FAIL $f @${w}: exit $rc — the status line would go blank"
			failed=$((failed + 1))
			continue
		fi
		if [ ! -s "$out" ]; then
			echo "FAIL $f @${w}: no output — the status line would go blank"
			failed=$((failed + 1))
			continue
		fi
		if [ -s "$err" ]; then
			echo "FAIL $f @${w}: wrote to stderr: $(head -1 "$err")"
			failed=$((failed + 1))
			continue
		fi
		if grep -qE "(^|[^[:alnum:]_-])null([^[:alnum:]_-]|\$)" "$out"; then
			echo "FAIL $f @${w}: the word null reached stdout: $(grep -m1 'null' "$out")"
			failed=$((failed + 1))
			continue
		fi
		if [ -n "$charloc" ]; then
			wide=""
			while IFS= read -r line; do
				plain=$(printf '%s' "$line" | sed "s/${esc}\[[0-9;]*m//g")
				len=$(printf '%s' "$plain" | LC_ALL=$charloc wc -m | tr -d '[:space:]')
				if [ "$len" -gt "$w" ]; then
					wide="$len"
					break
				fi
			done <"$out"
			if [ -n "$wide" ]; then
				echo "FAIL $f @${w}: a row is $wide columns in a $w-column terminal — truncated from the right"
				failed=$((failed + 1))
				continue
			fi
		fi
		echo "ok   $f @${w}"
	done
done

if [ "$failed" -ne 0 ]; then
	echo "check-candidate: $cand FAILED $failed check(s)"
	exit 1
fi
echo "check-candidate: $cand survived every fixture"
