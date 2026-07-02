# cc-sessions

Make your past Claude Code sessions usable from your current one. Point at them, search them, ask questions of them, and continue work from them — without replaying whole transcripts into context.

Claude Code keeps every session as a local transcript, but out of the box there's no good way to *use* that history: `--resume` is a flat picker, and pasting old conversations into a new session burns context. cc-sessions turns your history into something you can reference in plain English, the way [Amp references threads](https://ampcode.com/manual#referencing-threads):

```
> Implement the plan we made in the session about the billing migration
> Apply the same fix from @session:8f14e45c to the settings page
> What did we decide about rate limits for the webhooks service, and did we ever ship it?
> Summarize @session:a3c59b12 as a handoff so I can continue in the frontend repo
```

## What you can do

- **Continue past work** — "implement the plan from that session" pulls out the *final* plan, not the draft that got revised, and none of the 200k tokens of deliberation around it.
- **Reapply a fix or technique** — reference a session by ID (or describe it) and apply what actually worked there to the code in front of you.
- **Find sessions by memory** — "last week we debugged why background jobs ran twice" — Claude searches your history, confirms the match, and answers from it.
- **Ask questions across your history** — "did we ever ship it?" fans out readers over multiple sessions and synthesizes an answer with per-claim citations, so you can jump back into any source session.
- **Produce handoff briefs** — goal, decisions, verified-vs-claimed state, exact commands, open threads — portable to another repo, machine, or teammate.

Everything runs locally. Nothing is sent anywhere.

## How it works

Three pieces:

| Piece | Role |
|---|---|
| [`ccsearch`](https://github.com/madzarm/ccsearch) | Discovery — hybrid keyword + semantic search over `~/.claude/projects/**/*.jsonl`, self-updating local index |
| [`skills/sessions`](skills/sessions/SKILL.md) | Teaches the main agent to resolve references, search, disambiguate, and dispatch readers |
| [`agents/session-reader.md`](agents/session-reader.md) | Opus subagent that iteratively reads one transcript and returns distilled, verified facts |

Two design rules do most of the work:

- **Extraction, not injection.** The main agent never reads a transcript directly — a reader subagent goes to it and returns only what the task needs, so your context stays clean no matter how big the referenced session is.
- **The reader is skeptical.** It follows the timeline forward to catch reverts, verifies tool calls actually succeeded before reporting "this was done", and distrusts compaction summaries when exact code or wording matters. In testing it produced an accurate handoff brief — including correctly flagging a pushed-but-never-tested final fix — from a 40MB, 8,700-line transcript that had been compacted 9 times.

## Install

The repo is its own plugin marketplace. In Claude Code:

```
/plugin marketplace add jalvarado91/cc-sessions
/plugin install cc-sessions@cc-sessions
```

Then set up the dependencies — either just tell Claude:

```
> set up cc-sessions
```

(the skill checks its own dependencies and runs the bundled setup script), or run it yourself:

```bash
sh ~/.claude/plugins/*/cc-sessions/skills/sessions/scripts/setup.sh
```

The script installs [`ccsearch`](https://github.com/madzarm/ccsearch) (brew, or the official installer into `~/.local/bin`) and `jq` (brew/apt/dnf/pacman/apk), then builds the search index. First index downloads a small (~80MB) local embedding model.

**Platforms:** macOS and Linux. Windows is untested (ccsearch supports it, but the skill's shell recipes assume a POSIX shell).

**Dependencies are required, not optional.** The skill is designed around real hybrid search and clean JSON projections; it deliberately refuses to fall back to grepping transcripts by hand.

## Development install

Working on the plugin itself? Symlink instead:

```bash
git clone https://github.com/jalvarado91/cc-sessions ~/Code/cc-sessions
ln -sfn ~/Code/cc-sessions/skills/sessions ~/.claude/skills/sessions
ln -sfn ~/Code/cc-sessions/agents/session-reader.md ~/.claude/agents/session-reader.md
sh ~/Code/cc-sessions/skills/sessions/scripts/setup.sh
```

Restart Claude Code sessions to pick up changes (agents register at session start).

## Background

The original design exploration — the "wishful user experience" this was built from — is kept as a historical reference in [docs/wishful-ux.md](docs/wishful-ux.md).

## License

MIT
