# The payload contract

Every field Claude Code writes to a status line command's stdin, which of them
can be **absent**, which can be **null**, and what the settings shape is.

> **Verified against Claude Code 2.1.241 — docs re-read 2026-08-23.**
> Observed behaviour in this file was seen at 2.1.239 and 2.1.240.
> If your client is newer than the line above, this file may be missing fields.
> Re-verify before trusting it — see [Keeping this current](#keeping-this-current).

**Date every field claim to the version it was read from.** Fields are added
with a stated minimum version — `prompt_id` needs 2.1.196, `pr.kind` needs
2.1.234 — and a status line written against a newer field silently loses that
segment on an older client rather than erroring.

**Three kinds of evidence appear here and they are marked, not blended.** Most
of this file is the published documentation. A few claims were **observed** in
payloads captured from live sessions, and one was **seen on screen**, which
nothing can re-check without a person looking. Where a section carries one of
those markers, weigh it accordingly: documented claims hold across clients,
observed ones describe the versions named.

## Keeping this current

This file is a promise that goes stale. The check is cheap:

1. Read the current docs at <https://code.claude.com/docs/en/statusline>.
2. Diff the **Available data** table and the full JSON schema against the
   tables below.
3. Run `jq -r 'to_entries|map(.key)|join(" ")'` over a real captured payload —
   `SKILL.md` has the capture procedure — and compare the top-level keys.
4. Update the banner above with the version you checked, whether or not
   anything changed. A banner that stops moving is the signal.

Absence from a capture is not evidence about a field. `pr`, `vim`, `worktree`,
`agent` and `workspace.repo` are absent from most sessions because most sessions
are not in those states.

## Configuration

`statusLine` in a settings file, `type` set to `command`, `command` pointing at
a script path or an inline shell command:

- `padding` — extra horizontal spacing in characters, default `0`
- `refreshInterval` — re-run every N seconds on top of the event-driven updates,
  minimum `1`. Set it for anything time-based, or when background work changes
  state while the session sits idle
- `hideVimModeIndicator` — suppress the built-in mode text when the candidate
  renders `vim.mode` itself

It runs on session start and resume, on each new assistant message, after a
compact finishes, on a permission-mode change, on a vim-mode toggle, and on the
refresh timer. Updates are debounced at 300ms and an in-flight run is cancelled
by the next trigger.

## Always present

`cwd`, `session_id`, `transcript_path`, `version`, `output_style.name`,
`model.id`, `model.display_name`, `workspace.current_dir`,
`workspace.project_dir`, `workspace.added_dirs`, `exceeds_200k_tokens`,
`fast_mode`, `thinking.enabled`, and the whole `cost` object —
`total_cost_usd`, `total_duration_ms`, `total_api_duration_ms`,
`total_lines_added`, `total_lines_removed`.

`cwd` and `workspace.current_dir` carry the same value; prefer the latter for
symmetry with `workspace.project_dir`, which is where the session was launched
and may differ once the working directory moves.

## Absent — the key is missing, not null

| field | present when |
|---|---|
| `session_name` | a custom name was set, or an AI-generated title exists. The default display name does not populate it |
| `prompt_id` | after the first user input |
| `workspace.git_worktree` | the current directory is inside a linked git worktree |
| `workspace.repo` | inside a git repository that has an `origin` remote. Carries `host`, `owner`, `name` |
| `effort.level` | the model supports the reasoning-effort parameter. One of `low`, `medium`, `high`, `xhigh`, `max` |
| `vim.mode` | vim mode is enabled |
| `agent.name` | running under an agent flag or agent settings |
| `pr` | an open pull request, or a GitLab merge request, is found for the branch. Removed once it merges or closes. `pr.review_state` and `pr.kind` may be absent independently |
| `worktree` | a worktree session. `branch` and `original_branch` may be absent for hook-based worktrees |
| `rate_limits` | subscriber sessions, after the first API response. Each window may be absent independently |

## Null — the key is present and its value is null

- `context_window.current_usage` — before the first API call, and again after a
  compact until the next call repopulates it
- `context_window.used_percentage`, `context_window.remaining_percentage` — may
  be null early in the session

## Inside a `rate_limits` window

**Observed, not documented.** The window shape below was read from payloads captured
from live sessions on 2026-08-22 against Claude Code 2.1.239, not from the
documentation page the rest of this file is taken from. Treat it as one version's
observed behaviour rather than a published contract: it is the weaker kind of
evidence, and it is marked so a reader can weigh it accordingly.

Two windows were present, `five_hour` and `seven_day`, each carrying exactly two
fields:

```json
{ "five_hour": { "used_percentage": 0.0, "resets_at": 0 },
  "seven_day": { "used_percentage": 0.0, "resets_at": 0 } }
```

`used_percentage` is a number, integral in one capture and fractional in another;
`resets_at` is a Unix timestamp in seconds. The values above are zeros on purpose —
the shape is the finding, and a real capture carries an account's actual usage.

The fixtures have encoded this shape since birth, built from the field list alone.
The captures did not correct them; they confirmed them, which is the whole result:
a shape inferred from a documented field name survived contact with a live session.
**Nothing in this repo holds the fixtures to this prose.** They agree today because
they were written together; a field added here and not to `fixtures/` will not fail
anything. `scripts/check-candidate.sh` referees CANDIDATES against the fixtures, not
the fixtures against this file. Change one, change the other by hand.

Note the field name is `used_percentage`, the same name the context window uses for
something entirely different. A candidate reading the wrong one gets a plausible
number rather than an error.

## The context window object

`total_input_tokens` is the sum of `input_tokens`, `cache_creation_input_tokens`
and `cache_read_input_tokens`; `total_output_tokens` is the output of the most
recent response. Both are `0` before the first response.
`context_window_size` is 200000 by default and 1000000 for extended-context
models. `used_percentage` is computed from **input tokens only** — reproduce
that formula exactly if computing it by hand, or the two numbers disagree.

`exceeds_200k_tokens` is a fixed 200k threshold on input, cache and output
combined, regardless of the actual window size, so on an extended-context model
it goes true while the bar is barely a third full.

## The agent panel's row context

**Observed, not documented.** The shape below was read from rows captured on
2026-08-22 against Claude Code 2.1.239 — four rows captured during one delegated
agent's lifetime — not from the documentation page the rest of this file is taken
from. Treat it as one version's observed behaviour rather than a published
contract.

`subagentStatusLine` is a settings key of its own, beside `statusLine`, and it is
handed a DIFFERENT object from the session payload the rest of this file
documents. Only `session_id`, `transcript_path` and `cwd` appear in both. There is
no model, no cost, no context window and no rate limits.

Top-level keys: `columns`, `cwd`, `prompt_id`, `session_id`, `tasks`, `transcript_path`

Task keys: `contextWindowSize`, `cwd`, `description`, `id`, `label`, `model`, `startTime`, `status`, `tokenCount`, `tokenSamples`, `type`

`references/subagent-row.json` is one captured row with every identifier replaced
by zeros. The two key lists above were transcribed from it by hand and **nothing
re-checks them**; `jq -r 'keys|join(" ")' references/subagent-row.json` is the diff,
and it takes a second.

`columns` is the terminal width. `tasks` carries one entry per delegated task, not
one per panel row. `status` was seen as `running` and then `completed` — the
command keeps being called after a task finishes, until the row is evicted, so a
row arriving is not evidence that anything is still working. `label` repeated
`description` for a local agent. `tokenSamples` was a one-element array holding the
same number as `tokenCount`, and `contextWindowSize` is the delegated model's
window, not the calling session's.

**Read from the client, not observed.** The rule below was read out of the Claude Code
binary at 2.1.239, not from a captured row and not from documentation. It is the
weakest evidence in this file, and it is here because the behaviour it explains
cost a session a false negative that was nearly recorded as a fact.

- The command runs only while at least one delegated task is live: first call
  about 300 ms in, then every 5 s, killed at a 5 s timeout.
- The key is read from the settings the SESSION STARTED WITH. A session that was
  already running when the key was added never calls the command, however many
  agents it runs; only a session started afterwards does. Reloading hooks does not
  change that. An earlier test ran a delegated agent with the key
  installed on disk, wrote no row, and the absence looked like a fact about
  delegated agents.
- Two task fields the client can send that the captures did not carry: `name`,
  present only when the agent was spawned with one, and `effort`.
- **stdout is not a status line here.** It is one JSON object per line,
  `{"id": ..., "content": ...}`, where `id` matches a task's id; a line that does
  not parse against that shape is logged and dropped. A command that prints a
  plain line — the thing `statusLine` wants — decorates nothing, and the only
  symptom is a panel that never changes.

## Output

stdout is displayed; each printed line becomes a row. ANSI colour codes work
where the terminal supports them, and OSC 8 hyperlinks work in terminals that
support them. Multi-line output carrying escape sequences is the most likely
combination to render badly — simplify to plain text when chasing a glitch.

Notifications share the right-hand side of the status line row, so a long line
truncates on a narrow terminal.

### What that looks like, observed

**Seen on screen, not captured.** No payload and no binary read can settle what follows:
the only referee is a person looking at a terminal. Observed 2026-08-23 in a real
terminal at Claude Code **2.1.240** — the version that session's own captured payload
reports in its `version` field, not the 2.1.241 installed on the machine and not yet
restarted into. This is a fourth kind of evidence in this file and the weakest of them:
the documentation, a captured payload and a read of the client binary can each be
re-checked by a script, and this cannot be re-checked at all without asking someone to
look.

The truncation above is documented; what was observed is its DIRECTION and its shape.

- **Truncation takes the right-hand end, and marks it with an ellipsis.** A 127-column
  bar at a terminal width of about 95 clipped at `16%…` — the context percentage, both
  usage windows, the countdown and the cost were the parts lost, while a model string
  and a session label that never change were the parts kept.
- **Every line a candidate prints is rendered.** A two-row candidate showed both rows,
  neither clipped. The "each printed line becomes a row" above had never been exercised
  here by anything.
- **The notification really does sit on the first row.** A right-aligned indicator was
  visible on the same row as the candidate's first line, which is the sharing this
  section describes, seen rather than inferred.
