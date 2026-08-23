#!/bin/sh
# Run one candidate against EVERY fixture and judge it the way Claude Code
# does. Run it yourself for a quick answer; CI runs the same script on every
# candidate in the repo.
#
#   sh scripts/check-candidate.sh candidates/default.sh
#
# The four failure modes are not invented here; they are what the published
# documentation says makes a status line go blank or show junk:
#
#   1. a non-zero exit                     — the status line goes blank
#   2. no output at all                    — the status line goes blank
#   3. anything on stderr                  — captured, and never displayed
#   4. the literal word null in stdout     — an absent or null field read
#                                            without a fallback, printed at the
#                                            user rather than handled
#
# Mode 4 is the one worth a harness. The others announce themselves the first
# time a candidate is installed; a null shows up only in the states a fixture
# has to construct on purpose — before the first API response, and again right
# after a compact.
set -u

cand=${1:-}
[ -n "$cand" ] || { echo "usage: sh scripts/check-candidate.sh <candidate>" >&2; exit 2; }
[ -f "$cand" ] || { echo "check-candidate: no such candidate: $cand" >&2; exit 2; }

fixtures=""
for f in fixtures/*.json; do
	[ -f "$f" ] && fixtures="$fixtures $f"
done
# Fail-closed, the direction every referee in this repo takes: an empty fixture
# set proves nothing about a candidate, so it is a refusal and not a pass.
[ -n "$fixtures" ] || { echo "check-candidate: no fixtures — nothing to referee" >&2; exit 2; }

err=$(mktemp "${TMPDIR:-/tmp}/statusline-cerr.XXXXXX") || exit 2
out=$(mktemp "${TMPDIR:-/tmp}/statusline-cout.XXXXXX") || exit 2
trap 'rm -f "$err" "$out"' EXIT

failed=0
for f in $fixtures; do
	COLUMNS=${COLUMNS:-100} LINES=${LINES:-30} export COLUMNS LINES
	sh "$cand" <"$f" >"$out" 2>"$err"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		echo "FAIL $f: exit $rc — the status line would go blank"
		failed=$((failed + 1))
		continue
	fi
	if [ ! -s "$out" ]; then
		echo "FAIL $f: no output — the status line would go blank"
		failed=$((failed + 1))
		continue
	fi
	if [ -s "$err" ]; then
		echo "FAIL $f: wrote to stderr: $(head -1 "$err")"
		failed=$((failed + 1))
		continue
	fi
	if grep -q 'null' "$out"; then
		echo "FAIL $f: the word null reached stdout: $(grep -m1 'null' "$out")"
		failed=$((failed + 1))
		continue
	fi
	echo "ok   $f"
done

if [ "$failed" -ne 0 ]; then
	echo "check-candidate: $cand FAILED on $failed fixture(s)"
	exit 1
fi
echo "check-candidate: $cand survived every fixture"
