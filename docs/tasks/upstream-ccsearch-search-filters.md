# Task: upstream PR to ccsearch — make `--days` / `--project` work on `search`

Instructions for an agent (run on Opus or better). Goal: contribute a fix to
https://github.com/madzarm/ccsearch so that `ccsearch search --days N --project P`
actually filters results, then update this plugin's skill to use the flags.

## Context

ccsearch is the search backend for the cc-sessions plugin. Its `search`
subcommand **parses `--days` and `--project` but never uses them** — every
search runs over the full all-time index. We verified this two ways:

1. Source read: `args.days` / `args.project` are consumed only by `cmd_index`
   and `cmd_list`, never by `cmd_search`.
2. Behavior: `ccsearch search "q" --no-tui --json --days 1` and `--days 3650`
   produce byte-identical output (same shasum).

Because of this, `skills/sessions/SKILL.md` currently tells the agent NOT to
pass these flags and to scope by project with a jq post-filter. That
post-filter runs after ranking/truncation, so recall suffers for
under-represented projects. Filtering belongs before ranking, inside ccsearch.

Line numbers below are as of upstream commit `bb2663c` (a clone may exist at
`~/Code/ccsearch`). **Start by syncing to current upstream master and
re-verifying the bug still exists** — if upstream has since wired these flags,
skip to "After the fix lands" below.

## Code map (all paths relative to the ccsearch repo)

- `src/cli.rs:30-70` — `SearchArgs`: `days: u32` (default 30) and
  `project: Option<String>` already exist and are documented in `--help`.
  Note the default of 30: see "Design decisions" before preserving it.
- `src/main.rs:72` — `cmd_search`: destructures `args` but never touches
  `days`/`project`; calls `search::hybrid_search(...)`.
- `src/search/mod.rs:24` — `hybrid_search(db, embedder, query, limit,
  bm25_weight, vec_weight, rrf_k, recency_halflife, exclude_projects, exact)`:
  1. `bm25::search(db, query, limit * 2, exact)` → per-session FTS5 candidates
  2. `vector::search(db, embedder, query, limit * 2)` → per-session vector candidates
  3. RRF fusion, then a loop over `fused.take(limit * 2)` that fetches each
     `SessionRow` and **already skips `exclude_projects` there** (line ~63)
  4. recency boost, sort, `truncate(limit)`
- `src/db/queries.rs:171` — `fts_search`: two branches (chunks FTS / sessions
  FTS), plain SQL with `WHERE chunks_fts MATCH ?1`.
- `src/db/queries.rs:237` — `vec_search`: scans all chunk embeddings (or
  session embeddings) in Rust, keeps best per session.
- `src/db/queries.rs:352` — `list_sessions`: **the pattern to reuse** — builds
  `WHERE 1=1` + optional `AND created_at >= ?` (days) + optional
  `AND project_path LIKE ?` (project, substring match).

## Recommended design: pre-filter with a session-id allowlist

Do NOT just add a `days`/`project` check next to the `exclude_projects` skip
in `hybrid_search`'s post-fusion loop. That filters after candidate generation
(`limit * 2` per modality), which reproduces the recall problem we're trying
to kill: a project with weak global rank yields empty scoped results even when
it has good matches.

Instead:

1. In `cmd_search` (or top of `hybrid_search`), resolve the flags into an
   optional allowlist: one SQL query
   `SELECT session_id FROM sessions WHERE <days/project predicates>`,
   reusing the exact predicate style of `list_sessions` (`created_at >=
   cutoff`, `project_path LIKE %p%`). If neither flag is active, pass `None`
   and change nothing about current behavior.
2. Thread `filter: Option<&HashSet<String>>` through:
   - `fts_search`: add `AND session_id IN (...)` to both SQL branches
     (rarray/`carray` if the rusqlite feature is enabled, otherwise build the
     placeholder list — check what deps allow; keep it simple).
   - `vec_search`: it already iterates rows in Rust — skip
     `session_id`s not in the set. Cheap and safe.
3. Leave the RRF/recency/exclude_projects logic untouched.

This keeps candidate generation itself scoped, so `limit * 2` candidates are
all *eligible* candidates.

## Design decisions to handle explicitly (put these in the PR description)

- **`--days` default is 30.** Today that default is dead; making it live would
  silently change every existing user's search to a 30-day window — bad.
  Change the field to `Option<u32>` (no default) so bare `search` stays
  all-time, and only an explicit `--days N` filters. Call this out in the PR.
- **`created_at` vs `modified_at`** for the days cutoff: `list_sessions` uses
  `created_at`; matching it is the consistent choice. Mention the choice in
  the PR and defer to the maintainer's preference.
- **Empty-result message** (`cmd_search`, ~line 115) should mention active
  filters ("no matches in the last N days / project P — retry without
  filters") so agents and humans don't misread a scoped miss as a global one.

## Process

1. Fork `madzarm/ccsearch` under `jalvarado91`, branch `search-filters`.
2. Re-verify the bug on upstream master (shasum experiment above) before
   writing code.
3. Implement per the design; `cargo fmt`, `cargo clippy`, `cargo test`
   (repo has `tests/` and `benches/` — add a test for the allowlist path,
   mirroring however existing search tests are structured).
4. Verify against a real index: run the shasum experiment again — outputs must
   now differ; `--project cc-sessions` must return only that project's
   sessions; no flags must remain byte-identical to pre-patch output.
5. Open the PR against upstream. Keep it small and single-purpose. Describe
   the bug (flags parsed but ignored), the fix, and the two design decisions
   above. Link nothing about cc-sessions; the fix stands on its own.

## After the fix lands (follow-up, separate change)

Update `skills/sessions/SKILL.md` in THIS repo:

- Re-enable `--days`/`--project` in the search recipe (gate on installed
  ccsearch version if the release is versioned).
- Remove the "flags are ignored" warning bullets and the jq project-scoping
  workaround.
- Keep the "empty result = reformulate the query" guidance; with working
  filters add: "…or retry without the filter."
