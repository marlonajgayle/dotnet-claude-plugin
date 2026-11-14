---
name: ship
description: "Run the whole dotnet-vsa pipeline for one change: spec-writer, implementer, the code, security and UX reviewers in parallel, the implementer again on their findings (up to a set number of rounds), the approver, and the documenter once the change is approved. Commits each step on the feature or bugfix branch so the reviews see what will merge. Stops for the user after the spec, on open questions, when findings remain after the last round, and at the approver's decision. Never pushes, opens a PR or merges unless asked. Use when the user says: ship this, build and review this end to end, run the pipeline, take this from spec to merge."
argument-hint: "<request | slug> [--auto] [--rounds N] [--no-docs] [--from implement|review|approve]"
---

# Ship

Request or slug: `$ARGUMENTS`

You coordinate; the agents do the work. Each runs in its own context, writes its result to a file, and returns a short summary. Read the files to decide what happens next, not the summaries.

## Options

- `--auto`: do not pause for the spec to be approved. Open questions in the spec still stop the run.
- `--rounds N`: review-and-fix rounds before giving up (default 2).
- `--no-docs`: skip the documenter.
- `--from implement|review|approve`: resume an earlier run for an existing slug.

## Step 0: Set up

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `SPECS_DIR`, `REVIEWS_DIR` and `BASE_REF`.

- If the argument names an existing spec (`<SPECS_DIR>/<slug>.md`), use it and start at implementation (or at `--from`). Otherwise treat the argument as a request.
- `git status --short` must be empty, unless resuming with `--from`. Otherwise ask the user to commit or stash first: the run commits as it goes, and must not sweep up unrelated changes.
- Tell the user, once, what this run will do: commit to the feature or bugfix branch after each step, never push, open a PR or merge unless asked, and stop at the points listed below.

Start a todo list with one item per step, so progress is visible.

## Step 1: Spec

Launch the `spec-writer` agent (`dotnet-vsa:spec-writer`) with the request. When it returns, read the spec.

- **Open questions:** stop and put them to the user. Resume with their answers by launching the spec-writer again to update the spec.
- Without `--auto`: show the spec's title, type, branch, requirements, steps and risk notes, and ask the user to approve it or say what to change. Do not implement an unapproved spec.

## Step 2: Implement

Launch the `implementer` agent (`dotnet-vsa:implementer`) with the slug. It creates the branch the spec names and verifies its work.

- If it stopped to ask a question, put the question to the user and resume it with the answer.
- If verification did not pass, stop and report: the reviewers should not review broken code.
- Commit everything on the branch: `git add -A && git commit -m "<type>: <spec title>"`, where `<type>` is `feat` for a feature and `fix` for a bugfix.

## Step 3: Review

First decide whether the UX reviewer has anything to look at. List the branch's changed files with `git diff --name-only <BASE_REF>...HEAD` (`BASE_REF` from Step 0's discovery). The user-facing surface is `*.razor`, `*.razor.cs`, `*.razor.css`, `*.cshtml`, `*.css`, `*.scss`, `*.js`/`*.ts` under `wwwroot/`, `*.resx`, images and icons, and any `*Validator.cs` or `*Errors.cs` (their messages reach users).

- **Something user-facing changed:** launch the `code-reviewer`, `security-reviewer` and `ux-reviewer` agents (`dotnet-vsa:code-reviewer`, `dotnet-vsa:security-reviewer`, `dotnet-vsa:ux-reviewer`) in the same message, so they run in parallel. Each needs only the slug.
- **Nothing user-facing changed:** launch only the code and security reviewers, in the same message. Write the UX report yourself, so the record is complete without spending a reviewer on it. `mkdir -p "<REVIEWS_DIR>/<slug>"`, then write `<REVIEWS_DIR>/<slug>/ux.md`:

  ```markdown
  # UX review: <slug>
  **Branch**: <branch> · **Commit**: <git rev-parse HEAD> · **Design doc**: not read · **Date**: <YYYY-MM-DD>
  **Verdict**: NOT APPLICABLE
  **Counts**: Critical 0 · High 0 · Medium 0 · Low 0

  No user-facing file changed against <BASE_REF>, so the ux-reviewer was not run. Written by the ship skill.
  ```

  Check the list again on every round: a fix that touches a validator or a page brings the UX reviewer back.

Then read `<REVIEWS_DIR>/<slug>/code.md`, `security.md` and `ux.md`. For each, note the verdict, the open Critical and High findings, and whether its **Commit** is `git rev-parse HEAD`. A report that is missing or names another commit counts as not done: launch that reviewer again once.

## Step 4: Fix and re-review

If any report has an open Critical or High finding, or a CHANGES REQUESTED verdict, and fewer than `--rounds` rounds have run:

1. Launch the `implementer` to address the findings in `<REVIEWS_DIR>/<slug>/`.
2. Commit: `git commit -am "fix: address review findings for <slug>"` (add new files with `git add -A` first).
3. Go back to Step 3 and run all three reviewers again. The approver requires every report to match the final commit, so a fix makes all of them stale.

When the rounds run out with findings still open, stop. Show the open findings, the files they cite, and what the implementer said about any it disagreed with, and ask the user how to proceed.

## Step 5: Decide

Launch the `approver` agent (`dotnet-vsa:approver`) with the slug and read `<REVIEWS_DIR>/<slug>/decision.md`.

- **HUMAN REVIEW:** stop. Show the risk level, failed gates and the reasons with their file references. That is the result of this run; the person decides.
- **MERGE:** go on to Step 6. The approver merges only when `approver.autoMerge` is on and a PR exists; otherwise the branch is ready but not merged.

## Step 6: Document

Unless `--no-docs`, launch the `documenter` agent (`dotnet-vsa:documenter`) with the slug, then commit its files: `git add <docs dir> && git commit -m "docs: <spec title>"`. Documentation-only commits after the review do not make the reports stale.

## Report

- The spec path and branch, and the commits made.
- For each review round: the verdicts and counts, and what was fixed.
- The decision, the risk level and the reasons, and whether anything was merged.
- The documentation path, if written.
- The next step for the user: usually `git push -u origin <branch>` and opening a PR. Offer to do it; do not do it unasked.

## Rules

- Stop at every stop point above; never answer an agent's question or an open spec question on the user's behalf.
- Never edit code yourself. Changes go through the implementer, so they are verified and reported.
- Never commit to `main` or `master`, push, open a PR or merge unless the user asks.
- Never skip the code or security reviewer. Skip the UX reviewer only when no user-facing file changed, and then write its not-applicable report as Step 3 describes. Never pass the approver a report that does not match `HEAD`.
