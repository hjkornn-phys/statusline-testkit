#!/bin/sh
# A two-row status line, sized to the terminal.
#
#   row 1  ⟨agent⟩ model ≡effort «session» · dir · branch ⚑●⇡N · vN.N.N
#   row 2  context bar · 5h/7d usage ⟲reset · cost
#
# Why two rows: Claude Code TRUNCATES a status line from the right rather than
# wrapping it. A single row therefore spends its width left-to-right and clips
# whatever is last — which is the numbers that move, while a model string and a
# session label that never change are the two guaranteed to survive. Splitting
# them keeps the meters out of truncation's reach, and means your eye only
# rescans the row that actually changed.
#
# The git markers:
#
#   ⚑  you are on the trunk (main/master)
#   ●  the worktree is dirty
#   ⇡N N commits on this branch that the remote does not have; ⇡new when the
#      remote has never seen the branch at all. Set STATUSLINE_REMOTE to pick
#      the remote; it defaults to origin.
#   ⑂  a linked git worktree
#   ⟨⟩ this session is a delegated agent
#
# Fallbacks everywhere, for the reason candidates/default.sh states at length:
# percentages are null before the first API response and after a compact; agent,
# session_name, worktree and effort are ABSENT, not null. `jq -r` prints the word
# null for both, at the user.
#
# Cost: two git calls, both with --no-optional-locks so a status line never
# writes to the index of a repository you are working in. Updates are debounced
# at 300ms and an in-flight run is cancelled by the next trigger, so a third call
# would be a stale bar, not a richer one. Measured at ~84ms per render.

remote=${STATUSLINE_REMOTE:-origin}
input=$(cat)
j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

model=$(j '.model.display_name // "claude"')
dir=$(j '.workspace.current_dir // .cwd // ""')
pct=$(j '.context_window.used_percentage // 0 | floor')
cost=$(j '.cost.total_cost_usd // 0')
agent=$(j '.agent.name // empty')
sname=$(j '.session_name // empty')
wt=$(j '.workspace.git_worktree // empty')
over=$(j '.exceeds_200k_tokens // false')

# Reasoning effort, ABSENT rather than null whenever the model does not support
# the parameter — three fixtures construct that. It is the only session
# parameter that changes mid-session, through `/effort`, and shows nowhere else
# on screen, which is why it is here and `thinking`, `fast_mode` and
# `output_style` are not: those are live too and nothing has ever paid for them.
eff=$(j '.effort.level // empty')

# The client version. This is the one field this project has PAID for: dating an
# observation to the running client meant reading a captured payload, because
# the running version and the installed one are different things and only this
# field knows the first.
cver=$(j '.version // empty')
u5=$(j '.rate_limits.five_hour.used_percentage // empty')
u7=$(j '.rate_limits.seven_day.used_percentage // empty')
r5=$(j '.rate_limits.five_hour.resets_at // empty')

# One call for branch AND dirty: the porcelain -b header carries the branch,
# every line after it is a change. A directory outside a repository yields
# nothing and prints nothing, which is the required behaviour — an error in
# the bar is worse than an empty segment.
git_state=$(git -C "${dir:-.}" --no-optional-locks status --porcelain=v1 -b 2>/dev/null)
branch=""
dirty=""
if [ -n "$git_state" ]; then
	head_line=$(printf '%s\n' "$git_state" | head -1)
	branch=${head_line##\#\# }
	branch=${branch%%...*}
	case "$branch" in *"(no branch)"*) branch="detached" ;; esac
	[ "$(printf '%s\n' "$git_state" | wc -l)" -gt 1 ] && dirty="●"
fi

# The unpushed count, against a named remote. A branch the remote has never seen
# is ⇡new — distinct from ⇡0, because "never pushed" and "pushed and current" are
# the two states this glyph exists to tell apart.
ahead=""
if [ -n "$branch" ] && [ "$branch" != "detached" ]; then
	n=$(git -C "$dir" --no-optional-locks rev-list --count "refs/remotes/${remote}/$branch..HEAD" 2>/dev/null)
	if [ -z "$n" ]; then
		git -C "$dir" remote 2>/dev/null | grep -qx "$remote" && ahead="⇡new"
	elif [ "$n" -gt 0 ] 2>/dev/null; then
		ahead="⇡$n"
	fi
fi

case "$branch" in
"" ) segment="—" ;;
main | master ) segment="${branch}⚑" ;;
* ) segment="$branch" ;;
esac
[ -z "$wt" ] || segment="$segment ⑂${wt}"
[ -z "$dirty" ] || segment="$segment$dirty"
[ -z "$ahead" ] || segment="$segment $ahead"

filled=$((pct / 10))
bar=""
i=0
while [ "$i" -lt 10 ]; do
	if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
	i=$((i + 1))
done
if [ "$pct" -ge 85 ]; then c=31; elif [ "$pct" -ge 60 ]; then c=33; else c=32; fi

# TWO ROWS, and the reason is what the harness does at the edge: it TRUNCATES a
# status line from the right with an ellipsis rather than wrapping it. So a
# single row spends its budget left-to-right and the segments it clips first are
# the ones furthest right — here, the meters that actually move — while the
# model string and a session name that never change are the two guaranteed to
# survive. Observed in a real terminal at its default zoom: the bar ran
# to 127 columns, clipped at `16%…`, and the usage, countdown and cost were gone.
#
#   row 1  where you are    — near-static: repo, branch, dirty, ahead, identity
#   row 2  what it costs    — every part of it moves on its own
#
# Splitting them also means the eye only rescans the row that changed.
cols=${COLUMNS:-80}

# Display width, not byte length. Every block glyph in the meter is three bytes,
# so `${#s}` and `awk length` both report a 47-column row as 67 and would size
# this bar against a number that has nothing to do with the screen. `wc -m`
# counts characters. COLUMNS itself arrives in the environment because the
# output is captured rather than attached to a tty — `tput cols` in here reads
# nothing, which SKILL.md records.
vis() { printf '%s' "$1" | wc -m | tr -d ' '; }

# Subscription usage, and the reason every label here is load-bearing.
# `used_percentage` is the field name of two different quantities in this one
# payload — the context window's, already on the bar above, and a rate-limit
# window's. CONTRACT.md records that a candidate reading the wrong one
# gets a plausible number rather than an error, which is the failure mode this
# repo exists for. With both on one bar the `5h` and `7d` labels are what keep
# them apart, so they are not decoration.
#
# The shape inside a window is OBSERVED, not documented — one client version,
# 2.1.239, recorded in CONTRACT.md as the weakest kind of evidence
# that file carries. Each window is absent independently and the whole object is
# null before the first API response, so every part below degrades on its own
# and the segment disappears rather than printing a fallback nobody asked for.
#
# A real payload carried 28.999999999999996 here. Rounded, or that is the bar.
usage=""
[ -z "$u5" ] || usage="5h $(printf '%.0f' "$u5")%"

# The countdown, on the five-hour window only: it is the one that blocks a
# session, and a second countdown costs width the bar does not have. A reset
# already in the past prints nothing — every fixture's timestamp is one, which
# is why the pin for this builds its own future window instead of reading a
# fixture.
if [ -n "$usage" ] && [ -n "$r5" ]; then
	left=$((r5 - $(date +%s)))
	if [ "$left" -gt 0 ]; then
		h=$((left / 3600))
		m=$((left % 3600 / 60))
		if [ "$h" -gt 0 ]; then cd_="${h}h${m}m"; elif [ "$m" -gt 0 ]; then cd_="${m}m"; else cd_="<1m"; fi
		usage="$usage ⟲${cd_}"
	fi
fi

if [ -n "$u7" ]; then
	[ -z "$usage" ] || usage="$usage · "
	usage="${usage}7d $(printf '%.0f' "$u7")%"
fi

# Coloured on the five-hour value at the same thresholds as the context bar, so
# one reading of "amber means think about it" covers both numbers.
uc=32
if [ -n "$u5" ]; then
	u5i=$(printf '%.0f' "$u5")
	if [ "$u5i" -ge 85 ]; then uc=31; elif [ "$u5i" -ge 60 ]; then uc=33; fi
fi

# ROW 2 first, because it has no width decisions to make: it is short in every
# session state the fixtures construct, and it is the row that must never be
# clipped.
meters="$(printf '\033[%sm%s %s%%\033[0m' "$c" "$bar" "$pct")"

# The documented trap: this flag is a fixed 200k threshold on input, cache and
# output combined, so on an extended-context model it goes true while the bar is
# barely a third full. Shown as its own marker precisely because the bar does
# not imply it.
[ "$over" = "true" ] && meters="$meters !200k"
[ -z "$usage" ] || meters="$meters · $(printf '\033[%sm%s\033[0m' "$uc" "$usage")"
meters="$meters · \$$(printf '%.2f' "$cost" 2>/dev/null || echo "$cost")"

# ROW 1, built from the most operational thing outward and elided from the least.
# The branch and dirty markers are why this row exists; the directory names the
# repo; the model is context; the session name is a label you chose and can
# recognise from a fragment. So the name is what shrinks, and it shrinks BEFORE
# the harness gets a chance to cut the branch marker off the other end.
place="${dir##*/} · $segment"

# `≡` and not a gear or a lightning bolt, and the reason is arithmetic rather
# than taste: the width maths below counts with `wc -m`, one column per
# character, and a glyph with emoji presentation renders TWO columns in most
# terminals. Picking one would corrupt every width decision this candidate makes
# while every check here stayed green — a defect invisible to the referee that
# exists to catch it. U+2261 has no emoji presentation anywhere.
base=""
[ -z "$agent" ] || base="⟨${agent}⟩ "
base="$base$model"
[ -z "$eff" ] || base="$base ≡${eff}"

ver=""
[ -z "$cver" ] || ver=" · v${cver}"

# The ladder, least operational first, and every rung is REAL: the version is a
# fact about the binary and sheds first, the session name second (truncated if
# that is enough, dropped if it is not), the model's parenthetical third, the
# effort marker fourth. The directory and the branch never go — they are why row
# 1 exists — and below the floor the harness truncates from the right exactly as
# it did before this candidate had two rows.
#
# The order is load-bearing and it was WRONG in this candidate's first draft:
# the name was sized against a budget that already reserved room for the
# version, so the version silently outranked the name and the second rung was
# dead code. Two orders that produce the same bytes at every width are one
# order, and a check cannot referee the difference: the checker only asserts the
# bar does not blank and leaks no null, and it stayed green with the rungs
# swapped. Found by swapping them and reading the output at each width by hand.
lead="$base"
[ -z "$sname" ] || lead="$base «${sname}»"
row1="$lead · $place$ver"

if [ "$(vis "$row1")" -gt "$cols" ]; then
	ver=""
	row1="$lead · $place"
fi

if [ "$(vis "$row1")" -gt "$cols" ] && [ -n "$sname" ]; then
	room=$((cols - $(vis "$place") - $(vis "$base") - 6))
	if [ "$room" -ge 8 ]; then
		short=$sname
		[ "$(vis "$sname")" -le "$room" ] || short="$(printf '%s' "$sname" | cut -c1-$((room - 1)))…"
		lead="$base «${short}»"
	else
		lead="$base"
	fi
	row1="$lead · $place$ver"
fi

if [ "$(vis "$row1")" -gt "$cols" ]; then
	bare=""
	[ -z "$agent" ] || bare="⟨${agent}⟩ "
	bare="$bare${model%% (*}"
	[ -z "$eff" ] || bare="$bare ≡${eff}"
	row1="$bare · $place$ver"
fi
if [ "$(vis "$row1")" -gt "$cols" ]; then
	bare=""
	[ -z "$agent" ] || bare="⟨${agent}⟩ "
	row1="$bare${model%% (*} · $place$ver"
fi

printf '%s\n%s\n' "$row1" "$meters"
