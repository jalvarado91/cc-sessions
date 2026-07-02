# cc-sessions

Reference past Claude Code sessions the way [Amp references threads](https://ampcode.com/manual#referencing-threads): point at them, search for them, ask questions of them, and continue from them — without replaying whole transcripts into context.

```
> Implement the plan we made in the session about the billing migration
> Apply the same fix from @session:8f14e45c to the settings page
> What did we decide about rate limits for the webhooks service, and did we ever ship it?
> Summarize @session:a3c59b12 as a handoff so I can continue in the frontend repo
```

See [docs/wishful-ux.md](docs/wishful-ux.md) for the full design.

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

The script installs [`ccsearch`](https://github.com/madzarm/ccsearch) (brew, or the official installer into `~/.local/bin`) and `jq` (brew/apt/dnf/pacman/apk), then builds the search index. First index downloads a small (~80MB) local embedding model. Everything stays on your machine — nothing is sent anywhere.

**Platforms:** macOS and Linux. Windows is untested (ccsearch supports it, but the skill's shell recipes assume a POSIX shell).

**Dependencies are required, not optional.** The skill is designed around real hybrid search and clean JSON projections; it deliberately refuses to fall back to grepping transcripts by hand.

## How it works

Three pieces, all local:

| Piece | Role |
|---|---|
| [`ccsearch`](https://github.com/madzarm/ccsearch) | Discovery — hybrid BM25 + semantic search over `~/.claude/projects/**/*.jsonl`, self-updating index |
| [`skills/sessions`](skills/sessions/SKILL.md) | Teaches the main agent to resolve references, search, disambiguate, and dispatch readers |
| [`agents/session-reader.md`](agents/session-reader.md) | Opus subagent that iteratively reads one transcript and returns distilled, verified facts |

The main agent never reads a transcript directly. The reader is skeptical by design: it follows the timeline forward to catch reverts, verifies tool calls actually succeeded, and distrusts compaction summaries when exactness matters. In testing it produced an accurate handoff brief — including correctly flagging a pushed-but-never-tested final fix — from a 40MB, 8,700-line transcript that had been compacted 9 times.

## Development install

Working on the plugin itself? Symlink instead:

```bash
git clone https://github.com/jalvarado91/cc-sessions ~/Code/cc-sessions
ln -sfn ~/Code/cc-sessions/skills/sessions ~/.claude/skills/sessions
ln -sfn ~/Code/cc-sessions/agents/session-reader.md ~/.claude/agents/session-reader.md
sh ~/Code/cc-sessions/skills/sessions/scripts/setup.sh
```

Restart Claude Code sessions to pick up changes (agents register at session start).

## License

MIT
