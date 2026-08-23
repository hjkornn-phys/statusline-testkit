---
name: statusline-testkit
description: Use when building, changing, or debugging a custom status line for Claude Code — the shell command configured under statusLine that receives session JSON on stdin and prints the bar at the bottom of the interface. Covers the payload contract, the states that make a status line go blank, and a fixture harness for trying a candidate without installing it.
---

# statusline-testkit

A status line is a shell command. Claude Code runs it, writes a JSON payload
describing the session to its stdin, and displays whatever it prints on stdout.
Everything hard about writing one comes from that sentence: the payload changes
shape with the session state, and a command that mishandles the change does not
error — it goes blank.

## The procedure

1. **Write a candidate into `candidates/`.** One file, reads stdin, prints one
   or more lines. `candidates/default.sh` is a working example to copy.
2. **Render it against a fixture** to see what it looks like:
   `sh scripts/render.sh candidates/<yours>.sh fixtures/steady.json`. The
   renderer shows exit code, stdout and stderr separately, because the caller
   treats those three very differently.
3. **Check it against every fixture**:
   `sh scripts/check-candidate.sh candidates/<yours>.sh`. This is the referee —
   CI runs the same script over every candidate in the repo.
4. **Install it only when it survives.** `CONTRACT.md` records the
   `statusLine` settings shape, including `padding`, `refreshInterval` and
   `hideVimModeIndicator`.

## The four ways a status line fails, and only one is interesting

A non-zero exit, no output at all, or anything written to stderr all blank the
line, and all three announce themselves the first time you install a candidate.

The fourth does not. **A field read without a fallback prints the word `null` at
the user**, and only in session states you cannot reach by trying it once:
before the first API response, and again immediately after a compact. That is
what the fixtures are for — each one constructs a state that is otherwise
minutes of waiting or impossible to trigger on purpose.

## The distinctions worth not blurring

- **Absent is not null.** Optional objects are missing from the payload
  entirely, not present-and-null. `// empty` is the fallback for those; `// 0`
  or `// "—"` for the ones documented as nullable. Reading either without a
  fallback yields the same visible `null`, which is why the check greps stdout
  for that word rather than trusting the shape.
- **The terminal width does not come from the terminal.** Claude Code captures
  the output instead of connecting it to a tty, so width detection from inside
  the script reads nothing. The width arrives in the `COLUMNS` environment
  variable; `LINES` comes with it. Both harness scripts set them, so a candidate
  that sizes its output is exercised the way it will actually run.
- **Overflow truncates; it does not wrap, and the direction is a design input.**
  A row wider than `COLUMNS` is TRUNCATED from the right, not wrapped — so the order a candidate
  assembles its segments in decides which ones survive a narrow terminal. Whatever goes last is
  what a zoomed-in reader loses first. Observed at Claude Code 2.1.240: a 127-column bar clipped
  at `16%…`, throwing away the context percentage, usage, countdown and cost while keeping a
  model string and a session label that never change. **Every line a candidate prints is
  rendered**, so putting what MOVES on a second row is how it is kept out of truncation's reach.
  Nothing here referees any of this — it was established by looking at a terminal.
- **The payload describes the session, not the repository.** There is no branch,
  no dirty flag, and no ahead/behind count in it. A status line that shows git
  state runs git itself, in `workspace.current_dir`, with stderr discarded — a
  directory outside a repository must not print an error into the bar.
- **A slow candidate is a stale bar.** Updates are debounced and an in-flight
  run is cancelled when a new one triggers, so a candidate that shells out to
  something slow shows old data rather than late data.

## What the harness does not cover, stated so it is not assumed

- **The fixtures are BUILT from the published field contract, not captured from
  a live session** — but they have since been CHECKED against two that were.
  Every field two live payloads carried is present in the fixture set, and the
  `rate_limits` window shape the fixtures had invented from a field name turned
  out to match. See the capture procedure below; the confirmation is narrow, at
  one version, in one session state.
- **Git state cannot be fixtured.** A fixture's `current_dir` is a path that
  does not exist on this machine, so the git segment of a candidate renders its
  no-repository fallback under the harness. Exercise that segment in a real
  repository by hand.
- **Nothing here referees appearance.** The checker asserts a candidate does not
  blank the line or leak a null. Whether the result reads well is yours.

## Capturing a real payload

The fixtures are built from a documented contract, and the only way to know
whether that contract matches what a session sends is to catch one. It costs a
change to a live harness, which is why it is a procedure and not a habit.

Point `statusLine` at a wrapper that reads stdin once, writes it to a file, and
passes the same bytes to the candidate. Read the payload only through the
variable — a wrapper that runs `cat` twice gets nothing the second time, and the
bar goes blank.

Three things that are not obvious, each of which cost something here:

1. **Key the capture by `session_id`: a status line configured in user settings runs in EVERY session on the machine**, so a single fixed
   capture path is last-writer-wins. The first capture taken here belonged to a
   different session in a different directory, and read as the current one's
   until the directory inside it disagreed.
2. **The tee must not be able to blank the bar.** Swallow its failure and render
   anyway. A capture that breaks the status line to record itself has traded the
   thing being studied for the study.
3. **Back the settings file up before editing, and say so.** The install is
   reversible; an install nobody can reverse is a change to someone's machine
   rather than an experiment on it.

Set `refreshInterval` while capturing, so a session that is sitting idle still
re-renders and still writes.

**What the captures here showed, so a reader knows what to expect.** No field
appeared that the fixture set lacked. The `!200k` flag was observed true at 23%
of a one-million-token window, which is the documented trap seen live rather
than constructed. And a rate-limit window's `used_percentage` is a different
number from the context window's field of the same name.

### The agent panel is a different setting, and a different payload

`subagentStatusLine` is its own settings key, and its stdin is a different
object: no model, no cost, no context window, no rate limits, and a `tasks`
array the session payload has no equivalent of. A candidate written against the
contract above does not fit it. The shape is recorded in
`CONTRACT.md`, captured rather than guessed, with the one example
kept in `references/subagent-row.json`.

Its stdout is a different contract too — one `{"id": ..., "content": ...}` JSON
object per line, not a rendered bar — so a `statusLine` command pointed at this
key decorates nothing and reports nothing.

**A panel that never fires is the first thing to check, and the cause is not the
script.** The key is read from the settings a session STARTED with: add it while
a session is running and that session will never call it, however many agents it
runs. Start a new one. This cost a session here a false negative it nearly wrote
down as a finding about delegated agents.

**No captured payload has ever carried `agent.name`, so that segment is unexercised** by any live session — it is
pinned behaviourally against a fixture, renders correctly there, and has never
run against the state it was written for. A firing agent panel does not change
that, and is the likeliest thing to be mistaken for changing it.

The row context carries no `agent.name`, so a firing panel does not exercise
the segment — it is a different command reading a different object, and the
delegated agent's identity reaches it as `tasks[].name`, which is present only
when the agent was spawned with a name. The documented condition for that
field is a session running under an agent flag or agent settings, which is not
the same thing as a delegated subagent inside a session. Treat a candidate's
agent segment as unproven until a capture carries the field.

## Longer material

- `CONTRACT.md` — the field contract: what is always present, what is
  absent, what is null and when; the settings shape; and the two repository
  constraints that shape what may be written down here.

## Growing this file

**The only referee in this repo is behavioural**, and it referees candidates, not
this file: `scripts/check-candidate.sh` runs a candidate against every fixture and
fails on a blank bar or a leaked `null`. CI runs it over `candidates/`. Prose added
here is refereed by nothing, so anything claimed as observed carries the version it
was observed at, and anything documented carries a link — a reader has to be able to
re-check it, because no check will.
