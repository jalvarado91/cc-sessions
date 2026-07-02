---
name: sessions
description: Search, reference, and extract from past Claude Code sessions. Use when the user references a previous session or conversation ("that session where…", "we discussed this last week", "@session:<id>", "implement the plan from…", "apply the same fix from…"), asks what was decided or done in past work, wants to search their session history, or wants a handoff brief from another session.
---

# Referencing past sessions

Past Claude Code sessions are local JSONL transcripts. This skill makes them first-class references: findable by memory, addressable by ID, and readable through a subagent so the main context stays clean.

**Core rule: extraction, not injection.** Never read a session transcript wholesale into the main conversation. Discovery happens via `ccsearch`; reading happens inside a `session-reader` subagent that returns only distilled facts.

## Resolving a reference

- `@session:<id>` or a bare session UUID → resolve to a path:
  `ls ~/.claude/projects/*/<id>.jsonl`
- A described memory ("the session where we debugged X") → search (below), then confirm.
- A subagent hit (`agent-…` id) → its parent session is the directory it lives under:
  `ls ~/.claude/projects/*/*/subagents/agent-<id>.jsonl` → parent is the `<session-id>` path component.

## Searching history

`ccsearch` (https://github.com/madzarm/ccsearch) maintains a local hybrid index automatically.

**IMPORTANT:** raw `--json` output embeds full transcripts (`full_text`) — always pipe through this projection, never dump it raw:

```bash
ccsearch search "QUERY" --no-tui --json --limit 10 | jq '[.[] | {
  id: .session_id, score,
  project: .session.project_path,
  modified: .session.modified_at,
  msgs: .session.message_count,
  first_prompt: (.session.first_prompt // "" | .[:150]),
  matched: (.matched_text // "" | .[:200])
}]'
```

- Search always covers **full history**: `--days` and `--project` are accepted but ignored by `search` (they only work on `ccsearch list`) — do not pass them or retry with "wider" values. Ranking already favors recent sessions via a recency boost, so recent work surfaces first anyway.
- An empty result therefore means *no matches anywhere, ever* — reformulate the query (different words, `--exact` vs `--semantic`) rather than fiddling with flags.
- `--exact` for literal strings (error messages, function names); `--semantic` for concept-only matching; default hybrid is right most of the time.
- To scope to one project, filter the projection: append `| map(select(.project | test("myrepo")))`.
- Recency browsing without a query: `ccsearch list --days 7 --json | jq '…same projection idea…'` (`--days`/`--project` genuinely filter here).
- Results with `agent-…` ids are subagent transcripts; they're often the strongest content match but map them to their parent session before presenting.

## Confirming the match

- If the top result clearly matches (title/date/project line up with what the user described), proceed — but say which session you picked (title, date, project) so a wrong guess is cheap to correct.
- If ambiguous, present the top 3–4 candidates via AskUserQuestion with title, project, date, and first-prompt snippet.

## Extracting from a session

Dispatch the **session-reader** agent (it runs on Opus) with:

1. The absolute transcript path and session ID.
2. A *focused* question that includes what the answer is for — "extract the final plan for X; I'm about to implement it in repo Y" beats "summarize this session".

Ask for exactly what the task needs: the final plan, the fix that actually worked, the decision and its rationale, a handoff brief (goal · decisions · verified-vs-claimed state · exact commands · open threads).

**Cross-session questions** ("what did we decide about X across recent work?"): search first, pick the top 3–5 distinct sessions, fan out one session-reader per session **in parallel** (one message, multiple Agent calls), then synthesize — citing each claim's session ID, title, and date so the user can jump back in.

## After extraction

- Weave the distilled answer into the current task; include session IDs so the user can `claude --resume <id>` (works from the session's original project directory).
- If the reader flags something as claimed-but-unverified, carry that flag forward — don't launder it into fact.

## Requirements — hard dependencies, no fallbacks

`ccsearch` and `jq` are required. **Do not improvise a degraded substitute** (no grepping transcripts from the main context, no manual JSON parsing) — the quality of this skill depends on real search and clean projections.

On first use, verify both are present:

```bash
command -v ccsearch jq
```

If either is missing, run the setup script that ships alongside this skill file at `scripts/setup.sh` (when installed as a plugin: `"${CLAUDE_PLUGIN_ROOT}/skills/sessions/scripts/setup.sh"`; manual install: `~/.claude/skills/sessions/scripts/setup.sh`). It installs ccsearch (brew, or the official installer into `~/.local/bin`), jq (brew/apt/dnf/pacman/apk), and warms the index — macOS and Linux, fully local, no sudo except for system package managers. If the script fails, surface the error to the user and stop; don't work around it.

ccsearch's index self-updates before each search; the embedding model (~80MB) downloads once on first index.
