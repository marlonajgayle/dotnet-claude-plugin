---
name: review-pr
description: "Read-only pre-merge review of a vertical-slice .NET feature branch. Runs verify-conventions for the mechanical checks, then scores four dimensions (conventions, security, performance, spec conformance) with file:line citations and Critical/High/Medium/Low severity. Writes a report to the reviews folder (default .ai/reviews/<slug>.md) and prints a summary. Does not edit code, commit or push. Use when the user says: review this branch, review-pr, review my PR, code review before merge, check this branch against the spec."
argument-hint: "[slug]"
---

# Review PR

Optional slug: `$ARGUMENTS`

Read-only: do not edit code, commit or push. The only file you write is the report.

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER`, `AUTH_POLICIES`, `SPECS_DIR` and `REVIEWS_DIR`.

## Step 1: Scope

- No slug: read the current branch. If it is `main`/`master` or not `feature/*`, `bugfix/*` or `hotfix/*`, stop: `You're on '<branch>'. Check out a feature branch first, or pass a slug: review-pr <slug>`.
- Slug given: `git checkout feature/<slug>` (stop with the branch name tried if it does not exist).
- `<slug>` is the branch name minus its prefix. Read `<SPECS_DIR>/<slug>.md` if it exists; otherwise note "no spec found" and skip Dimension D.

## Step 2: Collect

In parallel: `git fetch origin main --quiet`, `git diff --stat origin/main...HEAD`, `git diff origin/main...HEAD`, `git log origin/main..HEAD --oneline`, `git status --short`. If the diff and status are both empty, stop: nothing to review.

## Step 3: Mechanical checks

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --changed-since origin/main --no-build
```

Every FAIL becomes a finding: handler-di, outbox and endpoint-auth are **Critical** (silent runtime failure or open endpoint); csproj is **High**. WARN items are **High** for soft-delete, **Medium** for rate-limit, utc-kinds and phantom-nav, after you confirm each by reading the code (drop false positives and say why).

## Step 4: Read and judge

Read every changed `.cs`, `.razor`, `.json` and `.csproj` file in full, plus `<PROGRAM_CS>`, `<OUTBOX_DISPATCHER>` and `<AUTH_POLICIES>`. Then score what a grep cannot.

**A. Conventions**
- Handlers return `Result`/`Result<T>`; expected failures use `{Entity}Errors`, not exceptions (High).
- `.Produces<>` metadata matches what the handler actually returns (Medium).
- Writes call `SetCreatedAuditInfo`/`SetModifiedAuditInfo`; deletes use `MarkAsDeleted()`, never `Remove` (High).
- `ExecuteUpdate`/`ExecuteDelete` on an aggregate that raises events (Critical: events dropped).
- Style: `sealed record` commands and queries, `sealed class` handlers, file-scoped namespaces, primary-constructor DI (Medium).

**B. Security**
- An endpoint that takes the caller's own resource id from the route or body, under a policy that does not check ownership: IDOR (Critical).
- User input without an `AbstractValidator<T>` (High).
- Secrets in `appsettings*.json` other than Local (Critical); PII, tokens or passwords in log properties (High).
- Raw SQL built by interpolation or concatenation (Critical).
- Sensitive fields stored unencrypted where sibling entities encrypt them (High).

**C. Performance**
- N+1: a per-item query inside a loop over query results (High).
- Read paths that load entities instead of projecting to a DTO (Medium).
- Two or more collection `Include`s without `AsSplitQuery()` (High).
- Unbounded `ToListAsync()` on a growing table (Medium).
- `CancellationToken` not accepted or not passed on (Medium).

**D. Spec conformance** (skip with no spec)
- Requirements the diff does not implement; Implementation Steps whose file is not in the diff; changed files not in the spec's Files Changed Summary (scope creep).

Mark anything that can only be confirmed by running the code as **needs verification**. Never guess.

## Step 5: Write `<REVIEWS_DIR>/<slug>.md`

```markdown
# Review: <slug>
**Branch**: <branch> · **Against**: origin/main · **Spec**: <path or "no spec found"> · **Date**: <YYYY-MM-DD>

## Summary
<Counts by severity and a verdict: ready to merge / needs fixes / blocked.>

## verify-conventions
<The table from Step 3.>

## Findings
### Critical
- `path:line` — what. **Why it matters:** … **Fix:** …
### High / Medium / Low
(omit empty headings)

## Spec conformance
## Recommendations
1. …
## Files reviewed
| File | NEW/MODIFY | Notes |
```

## Step 6: Chat summary

Branch, spec, counts per severity, the top three recommendations, and the report path.
