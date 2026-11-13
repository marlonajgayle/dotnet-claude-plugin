---
name: install-rules
description: "Copy or refresh the dotnet-vsa plugin's path-scoped rule files into the repo's .claude/rules/, showing a diff first, so the rules load only for the paths they apply to. Fallback for Claude Code versions that do not load a plugin's own rules directory. Use when the user says: install rules, update rules, sync plugin rules, refresh .claude/rules."
argument-hint: "[--check]"
---

# Install Rules

The plugin's rules live once in the plugin (`${CLAUDE_SKILL_DIR}/../../rules/`). This skill copies them into the repo's `.claude/rules/dotnet-vsa/`, where Claude Code loads `*.md` rule files and honours their `paths:` frontmatter. `--check` reports drift without writing anything.

## Step 1: Source

List `${CLAUDE_SKILL_DIR}/../../rules/*.md`. If the folder is missing or empty, stop: "This version of dotnet-vsa ships no rule files yet." Do not invent rules.

## Step 2: Compare

Target: `<repo root>/.claude/rules/dotnet-vsa/`. For each source file, classify it as **new** (no target), **unchanged** (identical) or **changed**, and show `diff -u <target> <source>` for each changed file. Also list target files with no source (rules removed from the plugin).

A changed target may hold local edits. Say so, and never overwrite it without the user's confirmation. Repo-specific rules belong in `.claude/rules/` outside the `dotnet-vsa/` folder, where this skill never writes.

## Step 3: Apply (unless `--check`)

After the user confirms: copy new and changed files, and delete removed ones only if the user agrees. Write `.claude/rules/dotnet-vsa/.source` containing the plugin version from `${CLAUDE_SKILL_DIR}/../../.claude-plugin/plugin.json`, so later runs can say what version is installed.

## Step 4: Report

New, updated, unchanged and removed counts; the installed version; and a reminder to commit `.claude/rules/dotnet-vsa/` so the whole team gets the same rules.
