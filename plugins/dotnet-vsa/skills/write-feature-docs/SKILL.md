---
name: write-feature-docs
description: "Write rich technical documentation for a feature of a vertical-slice .NET API in the docs folder (default docs/features/<slug>.md), structured like a DigitalOcean community tutorial: task-oriented title, introduction, key takeaways, prerequisites, numbered 'Step N — Doing X' sections with commands and labelled output, then an architecture diagram, API, error, event, configuration and data reference, troubleshooting, FAQs and a conclusion. Built from the spec, the code and the review reports, with every example traced to code. Updates the docs index. Use when the user says: document this feature, write docs, write-feature-docs <slug>, feature guide, update the docs for <feature>."
argument-hint: "<slug>"
---

# Write Feature Docs

Feature slug: `$ARGUMENTS`

The result is one guide a developer or API consumer can follow from nothing to a working use of the feature, with a reference they come back to later. The structure follows DigitalOcean's tutorials: tell readers what they will achieve and what they need, walk them through numbered steps that each show the command and what they should see, then recap and point them onward. The page template is in [template.md](template.md), and the writing rules are in [style.md](style.md). Read both before writing.

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `ROOT`, `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER`, `AUTH_POLICIES`, `RATE_LIMIT_POLICIES`, `SPECS_DIR`, `REVIEWS_DIR`, `DOCS_DIR` and `HEALTH_URL`.

- Empty argument: use the current branch name minus its `feature/`, `bugfix/` or `hotfix/` prefix. On `main` with no argument, reply `Usage: write-feature-docs <slug>` and stop.
- The page is `<DOCS_DIR>/features/<slug>.md`. If it exists, update it in place: keep sections that are still true, and change the **Last updated** line.

## Step 1: Gather the facts

Read, in this order:

1. The spec `<SPECS_DIR>/<slug>.md`: Context, Requirements, Affected surface, UX, Risk notes.
2. The reports in `<REVIEWS_DIR>/<slug>/`, especially `decision.md`. Note anything flagged as a known limitation.
3. The code the feature changed (`git diff --name-only <BASE_REF>...HEAD`, or `git log --grep <slug>` once merged) and read each file in full:
   - **Endpoints**: method, full route including the `MapGroup` prefix, authorization policy (and what the policy requires, from `AUTH_POLICIES`), rate-limit policy, request and response types, `.Produces<>` status codes.
   - **Requests and responses**: every property with its type, whether required, and its validator rules (`AbstractValidator<T>`).
   - **Errors**: each `{Entity}Errors` member the handlers return, with its code, message and the HTTP status `ToHttpResult()` maps it to.
   - **Domain events**: name, when it is raised, what its handler does, and that it is delivered through the outbox (so it is eventually consistent).
   - **Data model**: new or changed entities and properties, and the migration name.
   - **Configuration**: new `appsettings` sections and options classes, with defaults. Never copy a secret value; show a placeholder.
   - **Background jobs**: schedule, options and health check.
   - **UI**: the pages or components, their route, and what the user does on them.
4. The existing pages in `<DOCS_DIR>/` so links and terms match.

Every statement in the page must come from these sources. If something cannot be confirmed, leave it out or mark it `<!-- TODO: confirm ... -->` and list it in your report. Do not invent fields, status codes or behaviour.

## Step 2: Plan the steps

Choose 3 to 7 steps that take the reader through the feature in the order they would use it: configure, then create, then read, update, and the follow-on effects (events, emails, jobs). Each step has one goal and a gerund title: `## Step 2 — Creating an Invoice`. A step that has no command or action for the reader belongs in the Reference instead.

## Step 3: Write the page

Fill [template.md](template.md) following [style.md](style.md). For each step:

1. One or two sentences on what the step does and why.
2. The command or code, in a fenced block with a language. Requests are `curl` against the local base URL from `HEALTH_URL`, with placeholders such as `<access-token>` explained the first time they appear.
3. The expected output under an `**Output**` label, in a ```` ```text ```` or ```` ```json ```` block, matching the real response type.
4. One or two sentences on what the output means and what to notice in it, then a transition to the next step.

Then the Reference section: the Mermaid diagram, then the tables the feature needs (omit a table that would be empty). Then Troubleshooting from the errors the reader is most likely to hit, FAQs, and the Conclusion.

## Step 4: Check the examples

If the API can run locally, start it with `run-api` and run each `curl` from the steps, replacing the example output with what you observed (with ids, tokens and timestamps replaced by realistic placeholders). Set **Last validated** to today only if every example ran. Otherwise write `Last validated: not yet run against a live instance` and say which examples you could not run. Never claim an example was run when it was not.

Check that every relative link resolves to a file and every Mermaid block has a valid diagram type on its first line.

## Step 5: Update the index

`<DOCS_DIR>/README.md` lists every guide. Create it if missing, with a short intro and a `## Feature guides` table (`| Guide | What it covers | Last updated |`). Add or update this feature's row. Keep the rows sorted by title.

## Step 6: Report

The page path, the step titles, the reference tables included, whether the examples were validated, and every TODO left in the page.
