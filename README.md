# statusline-testkit

**A test harness for Claude Code status lines.** Works with any of them — yours,
one you copied, one you generated with `/statusline`.

Your bar works. You wrote it, you installed it, it looks right. Then someone
opens a fresh session and sees this:

```
Opus | demo | null% | $0
```

That is a real first draft, run against a real session state, caught by the
checker in this repo:

```
$ sh scripts/check-candidate.sh candidates/mine.sh
ok   fixtures/extended-context.json
FAIL fixtures/first-render.json: the word null reached stdout: Opus | demo | null% | $0
ok   fixtures/long-identity.json
ok   fixtures/no-git.json
ok   fixtures/post-compact.json
ok   fixtures/steady.json
ok   fixtures/worktree.json
check-candidate: candidates/mine.sh FAILED on 1 fixture(s)
```

`context_window.used_percentage` is **null** before the first API response. The
script is correct in every state you can reach by trying it, and wrong in the one
state every session begins in.

## Why this is worth a harness

A status line that fails does not report an error. **It shows nothing** — a
non-zero exit, no output, or a single byte on stderr all blank the bar silently.
Those three announce themselves the first time you install.

The fourth does not. A field read without a fallback prints the word `null` at
the user, and only in states you cannot trigger on purpose: before the first API
response, and again right after a `/compact`. You find it days later, in someone
else's screenshot.

## Use it on your own status line

```sh
git clone https://github.com/hjkornn-phys/statusline-testkit
cd statusline-testkit
cp ~/.claude/my-statusline.sh candidates/

sh scripts/check-candidate.sh candidates/my-statusline.sh   # the referee
sh scripts/render.sh candidates/my-statusline.sh fixtures/first-render.json
COLUMNS=60 sh scripts/render.sh candidates/my-statusline.sh fixtures/long-identity.json
```

No install, no settings change, no waiting for the state to happen to you.

## What the fixtures construct

Seven payloads, each built to break something different.

| fixture | the state |
|---|---|
| `first-render.json` | before the first API response — `used_percentage` **null**, `current_usage` **null**, no `rate_limits` |
| `post-compact.json` | right after `/compact` — `current_usage` **null** again while the percentage is back |
| `no-git.json` | a directory outside any repository |
| `worktree.json` | a linked worktree, running as a delegated agent — `agent` and `worktree` **present**, which they are not anywhere else |
| `extended-context.json` | a 1M-token model, one rate-limit window present and one **absent** |
| `steady.json` | the ordinary case, both windows present |
| `long-identity.json` | a long model name, session label and directory — forces truncation |

**Absent is not null**, and that distinction is most of the difficulty. Optional
objects are missing from the payload entirely, not present-and-null. `// empty`
is the fallback for those, `// 0` for the ones documented as nullable. Read
either without a fallback and the user sees `null`.

## Three traps that cost real debugging

**The terminal width does not come from the terminal.** Claude Code captures
your output instead of attaching it to a tty, so `tput cols` reads nothing. The
width arrives in `COLUMNS`. Both scripts here set it, so a bar that sizes itself
is exercised the way it will actually run.

**Overflow truncates from the right — it does not wrap.** So the order you
assemble segments in decides what a narrow terminal throws away, and whatever
you put last is what a zoomed-in reader loses first. Put the numbers that move
where truncation cannot reach them.

**A glyph is not always one column.** Characters with emoji presentation render
two columns wide, so any width arithmetic based on character counts is silently
wrong once one appears in your bar.

## What is in here besides the harness

[`CONTRACT.md`](CONTRACT.md) — every field, which can be absent, which can be
null, and the settings shape. It carries a *verified against* banner and a
procedure for re-checking it, because a contract file that goes quietly stale is
worse than none.

`candidates/default.sh` — a plain bar to copy.

`candidates/two-row.sh` — a worked example: two rows, sized to `COLUMNS`, with
git branch/dirty/unpushed markers, context bar, 5-hour and 7-day rate-limit
usage, a reset countdown, and a four-step elision ladder that sheds the least
important segment first as the terminal narrows.

## Building one with Claude

Point Claude Code at this repo and describe the bar you want. `SKILL.md` carries
the procedure, the failure modes and the payload contract, so Claude writes a
candidate, runs it against the fixtures, and iterates — without touching your
live settings until it survives.

## What this does not do

**It does not referee appearance.** The checker asserts your bar does not blank
and does not leak a `null`. Whether it reads well is yours.

**Git state cannot be fixtured.** A fixture's `current_dir` does not exist on
your machine, so git segments render their no-repository fallback here. A green
check proves they do not *blank*; it proves nothing about whether your branch or
dirty markers are correct. Exercise those by hand in a real repository.

## Contributing

Run `sh scripts/check-candidate.sh` on anything you add. CI runs the same script
over every candidate in `candidates/`.

## License

MIT — see [LICENSE](LICENSE).
