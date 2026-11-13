---
name: backlog-sync
description: "Keep the project backlog file (default .ai/backlog.md) current: add a newly discovered fix or enhancement in the F#/E# · priority · effort format with file pointers, or strike an item that a merge closed. Use after a merge, after discovering a defect or debt, or when the user says: add to backlog, log this, backlog item, strike from backlog, close F2, update the backlog."
argument-hint: "add <fix|enhancement> <title> | close <F#|E#> [branch or PR] | review"
---

# Backlog Sync

Arguments: `$ARGUMENTS`

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `BACKLOG_FILE` and `ROOT`. Read the whole file and learn its format before changing it. If it does not exist, ask before creating one with `## Fixes` and `## Enhancements` sections and a header explaining the priority and effort scale:

- **P1** wrong data, a security hole, or a user-visible failure; **P2** a real defect with a narrow trigger, or the next feature needed; **P3** polish and debt.
- **S** under half a day; **M** one to two days; **L** more.

## add

Heading in the file's existing style, numbered after the highest existing id in that section (`F` for fixes, `E` for enhancements):

```markdown
### F7 · P2 · S — <one-line title in plain words>
<What is wrong or missing, and who it affects. One short paragraph.>
**Fix:** <the proposed change.>
**Where:** `path/to/File.cs`, `path/to/Other.cs`.
**Check first:** <a dependency or risk, if any.>
```

Derive the priority and effort from the definitions above and say how you chose them; the user can override. Place the item in rank order within its section (P1 before P2 before P3, then by impact). Every **Where** path must exist; check each.

If the item came from a review or audit report, link the report.

## close

Find the item by id. Confirm it is done: the referenced change is on `main` (`git log main --oneline --grep` or the named branch or PR merged), or the user says so. Then follow the file's convention for closed items: either remove the item and add a line to a "Done" or "Recently closed" section (`F2 — <title> — closed <YYYY-MM-DD> by <branch/PR>`), or strike it through. If the file has no convention, use a "Recently closed" section at the end.

Never close an item whose fix you cannot confirm; ask instead.

## review

Report the items whose **Where** paths no longer exist, items that look already fixed (a quick Grep for the described problem), and the top three P1 items. Change nothing.

## Rules

- Keep the file's existing order, headings and tone. Never reflow or rewrite other items.
- Update the "Last reviewed" line, if the file has one, to today's date and the reason.
- Never commit; the user commits the backlog with the related change.
