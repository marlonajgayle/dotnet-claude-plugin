---
name: package-health
description: "Quick NuGet health check for a .NET solution: vulnerable packages including transitive ones (grouped by severity), deprecated packages, and outdated packages with a note on which updates cross a major version. Read-only. Use for a cheap standalone check or in CI: package health, outdated packages, vulnerable packages, dependency check, nuget audit, CVE in packages."
---

# Package Health

Read-only; it suggests commands but never runs `dotnet add package`.

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `SLN` (or `API_PROJECT` if there is no solution).

## Step 1: Query (in parallel)

```bash
dotnet list <SLN> package --vulnerable --include-transitive --format json
dotnet list <SLN> package --deprecated --format json
dotnet list <SLN> package --outdated --format json
```

`--format json` needs a recent SDK; if it is rejected, run the same commands without it and parse the tables. If restore or the feed fails (offline, auth), say which check was skipped and why, and continue with the rest.

When the plugin's `nuget` MCP server is connected, use its tools to fill in **Fixed in**: the best version compatible with the project's target framework that resolves every advisory, for direct and transitive packages alike. Use only its read tools here; this skill never changes package references. To apply the fixes, tell the user they can ask Claude to fix the vulnerable packages, which uses the server's update tools after confirming.

## Step 2: Classify

- **Vulnerable**: one line per package and advisory, grouped Critical → High → Moderate → Low, marking whether it is a top-level or a transitive dependency. For a transitive one, name the top-level package that brings it in and whether bumping that one fixes it; otherwise suggest pinning the fixed version with a direct `PackageReference`.
- **Deprecated**: the reason and the suggested alternative, if any.
- **Outdated**: split into patch/minor (usually safe) and **major** (read the release notes; breaking changes likely). Flag framework packages (`Microsoft.AspNetCore.*`, `Microsoft.EntityFrameworkCore.*`, `Microsoft.Extensions.*`) whose major version differs from the target framework's: those move together with the SDK, not one at a time.

## Step 3: Report

```markdown
## Package health — <solution>
Vulnerable: Critical N · High N · Moderate N · Low N | Deprecated N | Outdated N (M major)

### Vulnerable
| Package | Version | Severity | Direct? | Fixed in | Advisory |
### Deprecated
### Outdated
| Package | Current | Latest | Kind |
### Suggested commands
dotnet add <project> package <Name> --version <fixed>
```

If nothing is vulnerable, deprecated or outdated, say so in one line. `security-audit` includes this check as its first layer; this skill is the fast standalone version.
