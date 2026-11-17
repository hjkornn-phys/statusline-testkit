# statusline-testkit

**A status line for Claude Code that sizes itself to your terminal — and the
test harness that proves it.** The harness works on any bar: this one, yours,
one you copied, one you generated with `/statusline`.

## The bar

`candidates/two-row.sh` — two rows, so truncation cannot reach the numbers that
move. Git branch/dirty/unpushed markers, context bar, 5-hour and 7-day
rate-limit usage, a reset countdown, session cost, and an elision ladder on
each row that sheds the least important segment first as the terminal narrows:

```
COLUMNS=100
Opus 5 (1M context) ≡medium «a deliberately long session label» · some-rather-long-project-name · —
████░░░░░░ 41% · 5h 12% · 7d 34% · $3.50

COLUMNS=80  (the session label shrinks first)
Opus 5 (1M context) ≡medium «a deliberatel…» · some-rather-long-project-name · —
████░░░░░░ 41% · 5h 12% · 7d 34% · $3.50

COLUMNS=40  (label, parenthetical and effort gone; the directory itself shrinks; the branch state never goes)
Opus 5 · some-rather-long-project-n… · —
████░░░░░░ 41% · 5h 12% · 7d 34% · $3.50
```

`candidates/default.sh` — a plain single-row bar to copy, which sheds whole
segments from the right instead of getting clipped mid-glyph:

```
Opus | demo | — | ███████░░░ 77% | medium | $0.41      COLUMNS=80
Opus | demo | — | ███████░░░ 77%                       COLUMNS=40
```

Install either one:

```sh
cp candidates/two-row.sh ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh
```

then point `statusLine` in `~/.claude/settings.json` at it.

## Why you can trust it: every claim above is refereed

Your bar works. You wrote it, you installed it, it looks right. Then someone
opens a fresh session and sees this:

```
Opus | demo | null% | $0
```

That is a real first draft, run against a real session state, caught by the
checker in this repo. `context_window.used_percentage` is **null** before the
first API response. The script was correct in every state you can reach by
trying it, and wrong in the one state every session begins in.

A status line that fails does not report an error. **It shows nothing** — a
non-zero exit, no output, or a single byte on stderr all blank the bar
silently. Those three announce themselves the first time you install. The
fourth does not: a field read without a fallback prints the word `null` at the
user, and only in states you cannot trigger on purpose — before the first API
response, and again right after a `/compact`. You find it days later, in
someone else's screenshot.

So the checker runs a candidate against seven constructed states and judges it
the way Claude Code does — payload on stdin, verdict from what comes out:

- **exit non-zero, print nothing, or touch stderr** — fail; the bar would blank
- **the word `null` in the output** — fail; matched as a standalone token, so a
  repository named `null-safety` does not fail a correct bar
- **any row wider than the terminal** — fail; asserted at `COLUMNS` 40, 80 and
  100, counted in *characters with the color codes stripped*, never bytes — a
  ten-cell block meter is thirty bytes and ten columns
- your script is executed **directly, so its own shebang decides the shell** — a
  bash bar is judged as bash, not as whatever `/bin/sh` means on the machine
  running the check

Both shipped candidates are green on every fixture at every width, and CI runs
the same script on every candidate in the repo.

## Use it on your own status line

Requires `jq` (both shipped candidates use it; yours may not).

```sh
git clone https://github.com/hjkornn-phys/statusline-testkit
cd statusline-testkit
cp ~/.claude/my-statusline.sh candidates/
chmod +x candidates/my-statusline.sh

sh scripts/check-candidate.sh candidates/my-statusline.sh   # the referee
sh scripts/render.sh candidates/my-statusline.sh fixtures/first-render.json
COLUMNS=60 sh scripts/render.sh candidates/my-statusline.sh fixtures/long-identity.json
```

No install, no settings change, no waiting for the state to happen to you. A
failure names the fixture, the width and the reason:

```
FAIL fixtures/first-render.json @80: the word null reached stdout: Opus | demo | null% | $0
FAIL fixtures/long-identity.json @40: a row is 42 columns in a 40-column terminal — truncated from the right
```

## What the fixtures construct

Nine payloads, each built to break something different.

| fixture | the state |
|---|---|
| `first-render.json` | before the first API response — `used_percentage` **null**, `current_usage` **null**, no `rate_limits` |
| `post-compact.json` | right after `/compact` — `current_usage` **null** again while the percentage is back |
| `no-git.json` | a directory outside any repository |
| `worktree.json` | a linked worktree, running as a delegated agent — `agent` and `worktree` **present**, which they are not anywhere else |
| `extended-context.json` | a 1M-token model, one rate-limit window present and one **absent** |
| `steady.json` | the ordinary case, both windows present |
| `long-identity.json` | a long model name, session label and directory — forces truncation |
| `gateway-spend.json` | a gateway session — `rate_limits` carries only `spend_limit`, past 100%, no `five_hour` or `seven_day` (2.1.326, from the binary) |
| `gateway-spend-pct-only.json` | `spend_limit` with a percentage and no dollar figures, beside a lone `five_hour` (2.1.326, from the binary) |

**Absent is not null**, and that distinction is most of the difficulty. Optional
objects are missing from the payload entirely, not present-and-null. `// empty`
is the fallback for those, `// 0` for the ones documented as nullable. Read
either without a fallback and the user sees `null`.

## Three traps that cost real debugging

**The terminal width does not come from the terminal.** Claude Code captures
your output instead of attaching it to a tty, so `tput cols` reads nothing. The
width arrives in `COLUMNS`. The checker sweeps it, so a bar that sizes itself
is exercised the way it will actually run — and a bar that does not is told
exactly which row overflows which width.

**Overflow truncates from the right — it does not wrap.** So the order you
assemble segments in decides what a narrow terminal throws away, and whatever
you put last is what a zoomed-in reader loses first. Put the numbers that move
where truncation cannot reach them — or on their own row, which is why
`two-row.sh` has one.

**A glyph is not always one column.** Characters with emoji presentation render
two columns wide, so any width arithmetic based on character counts is silently
wrong once one appears in your bar. Every glyph the shipped candidates use is
chosen to be one column, and the comments in `two-row.sh` say why.

## The payload contract

[`CONTRACT.md`](CONTRACT.md) — every field, which can be absent, which can be
null, and the settings shape, with each claim graded by its evidence: published
documentation, observed in a captured payload, or read out of the client
binary — which are not the same kind of true. It carries a *verified against*
banner and a procedure for re-checking it, because a contract file that goes
quietly stale is worse than none.

## Building one with Claude

Point Claude Code at this repo and describe the bar you want. `SKILL.md` carries
the procedure, the failure modes and the payload contract, so Claude writes a
candidate, runs it against the fixtures, and iterates — without touching your
live settings until it survives.

## What this does not do

**It does not referee appearance.** The checker asserts your bar does not
blank, does not leak a `null`, and fits the terminal. Whether it reads well is
yours.

**Git state cannot be fixtured.** A fixture's `current_dir` does not exist on
your machine, so git segments render their no-repository fallback here. A green
check proves they do not *blank*; it proves nothing about whether your branch or
dirty markers are correct. Exercise those by hand in a real repository.

## Contributing

Run `sh scripts/check-candidate.sh` on anything you add — it must be executable
(`chmod +x`), since its own shebang decides the shell it is judged in. CI runs
the same script over every candidate in `candidates/`.

## License

MIT — see [LICENSE](LICENSE).
