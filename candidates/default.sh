#!/bin/sh
# A status line. Reads the session payload on stdin, prints one line on stdout.
#
#   model · directory · git branch · context bar · session cost
#
# Every field it touches is read with a fallback, because the payload's shape
# changes with the session state: percentages are null before the first API
# response, current_usage is null again after a compact, and workspace.repo, pr,
# effort, vim, agent and rate_limits are ABSENT — not null — when they do not
# apply. `jq -r` prints the word null for both, straight at the user, which is
# what `// empty` and `// 0` exist to stop.
set -u

input=$(cat)
j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

model=$(j '.model.display_name // "claude"')
dir=$(j '.workspace.current_dir // .cwd // ""')
pct=$(j '.context_window.used_percentage // 0 | floor')
cost=$(j '.cost.total_cost_usd // 0')
wt=$(j '.workspace.git_worktree // empty')
effort=$(j '.effort.level // empty')

# git is asked, not assumed: the payload says nothing about the branch, and a
# directory outside a repository must not print an error into the status line.
branch=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch="—"
[ -z "$wt" ] || branch="$branch ⑂$wt"

# A ten-cell bar. The percentage is input-only by definition upstream, so this
# matches what /context reports rather than inventing a second number.
filled=$((pct / 10))
bar=""
i=0
while [ "$i" -lt 10 ]; do
	if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
	i=$((i + 1))
done

# Colour by remaining room, not by taste: green under 60%, yellow to 85%, red
# above. A terminal without colour support still reads the number.
if [ "$pct" -ge 85 ]; then c=31; elif [ "$pct" -ge 60 ]; then c=33; else c=32; fi

line="$model | ${dir##*/} | $branch | $(printf '\033[%sm%s %s%%\033[0m' "$c" "$bar" "$pct")"
[ -z "$effort" ] || line="$line | $effort"
printf '%s | $%s\n' "$line" "$(printf '%.2f' "$cost" 2>/dev/null || echo "$cost")"
