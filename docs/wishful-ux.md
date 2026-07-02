# cc-sessions — Wishful User Experience

*Referencing past Claude Code sessions the way Amp references threads.*
*(See https://ampcode.com/manual#referencing-threads and https://ampcode.com/news/read-bigger-threads for the inspiration.)*

## The one-liner

> Any past session is a first-class thing I can point at, search for, ask questions
> of, and continue from — without ever opening the file or replaying the whole
> conversation.

## Background

**What Amp does:** You reference a thread by URL or `@T-<id>`, or type `@@` for an
inline search picker. There are no formal operators — you say "implement the plan
from @T-..." or "apply the same fix from @T-... here" and the agent infers intent.
Under the hood a `read_thread` subagent takes the thread + your question and
iteratively searches/reads it (their longest thread is ~21M tokens, so dumping it
into context is hopeless). Crucially, the reader *checks whether later work revised
or reverted what it found*, and distrusts compaction summaries when exact
wording/code/chronology matters.

**What we have locally:** Claude Code sessions live at
`~/.claude/projects/<munged-cwd>/<session-id>.jsonl` — typed JSONL records
(messages, tool calls/results, summaries), greppable and readable by an agent
today. [ccsearch](https://github.com/madzarm/ccsearch) solves discovery: local
hybrid search (SQLite FTS5 + local MiniLM embeddings), chunked indexing including
subagent transcripts, JSON output, auto-reindex.

**Structural difference from Amp:** their threads are server-hosted with stable
URLs and team-shareable; ours are local, per-machine, keyed by project directory.
So v1 is a *personal memory* feature, not a team one.

## The moments it serves

**1. "Pick up where that session left off" (the workhorse)**

```
> Implement the plan we made in the session about the billing migration
```

Claude searches history, confirms the match, then dispatches a **session-reader
agent** that extracts just the plan (final version, not the draft that got
revised) and implements it. Context stays clean — you get the plan, not 200k
tokens of how you arrived at it.

**2. "Do the same thing again, here"**

```
> Apply the same fix from @session:8f14e45c to the settings page
```

Reference by ID when you have it. The reader pulls the approach that *worked* —
verifying the fix landed and wasn't later reverted — and adapts it.

**3. "I don't have the ID, I have a memory"**

```
> Last week we debugged why background jobs ran twice — find that session
  and check whether the fix covered the retry case
```

No token at all. Claude searches history itself (ccsearch as the engine),
confirms the match ("found it: *duplicate job runs*, June 24,
acme-api — that one?"), then answers from it. Search is a tool the
agent has, not just a picker for the user.

**4. "Ask my history a question" (cross-session)**

```
> What did we decide about rate limits for the webhooks service, and did we ever ship it?
```

Spans multiple sessions. Fan out readers, synthesize, cite which session each
claim came from — with the ID so you can jump back in.

**5. "Hand off / continue elsewhere"**

```
> Summarize @session:a3c59b12 as a handoff so I can continue in the frontend repo
```

The reader produces a portable brief: goal, decisions, current state, what's
unverified, open threads. This is the escape hatch for "sessions are trapped in
one project directory" — and later, the seed of team sharing (a handoff doc is
shareable even when a JSONL isn't).

## Design principles (stolen deliberately from Amp)

- **No operators, no new grammar.** No `/fork`, `/import`, `/merge`. One
  reference primitive (`@session:<id>` + natural language) plus plain English
  intent.
- **Extraction, not injection.** A referenced session never gets pasted into
  context. A reader agent goes to it, so a 2M-token session costs a few hundred
  tokens of distilled answer.
- **The reader is skeptical.** It follows chronology forward ("was this later
  revised?"), verifies tool calls actually succeeded before reporting "we did X",
  and prefers original messages over summaries when exact code/wording matters.
  This is the difference between useful and confidently wrong.
- **Zero maintenance, fully local.** Index updates itself; nothing leaves the
  machine.

## Adaptation notes (Claude Code vs Amp)

- Amp's `@@` inline picker requires TUI changes we can't make. Our picker:
  Claude searches via ccsearch and confirms candidates with the user
  (AskUserQuestion) when the match is ambiguous.
- `@session:<id>` is a convention the skill teaches, not native syntax.

## Decisions

1. No separate CLI entrypoint (`claude --with-session <id>` etc.) — everything
   flows through conversation.
2. **Wrap ccsearch** as-is (shell out to `ccsearch search --json`) rather than
   rebuilding its indexing.
3. Packaging: skill (`sessions`) + subagent (`session-reader`) + ccsearch
   underneath, as user-level `~/.claude` config first. Make it **shareable as a
   plugin** once it works well for one person (repo is laid out plugin-shaped
   from day one).

## Deliberately out of scope for v1

- Team sharing / hosted threads (no server; handoff docs are the bridge)
- Editing or merging past sessions
- Auto-suggesting relevant past sessions unprompted (nice later, creepy/noisy first)

## Priority order

Moments 1 and 3 are the daily-driver wins; 4 is the demo; 2 and 5 fall out of
the same reader agent.
