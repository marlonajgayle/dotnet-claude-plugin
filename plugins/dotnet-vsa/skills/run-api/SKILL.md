---
name: run-api
description: "Start the ASP.NET Core API in the background (through its Aspire AppHost when it has one, otherwise with docker compose services started with -d when the repo has a compose file), poll /health until it answers, and report the URL, log path and shell id for Monitor. Never blocks the turn. 'run-api stop' stops it. Use when the user wants to run the API locally, observe runtime behaviour, or before smoke-health: run the api, start the app, boot the api, launch locally."
argument-hint: "[stop] [--no-infra] [--profile <launch-profile>]"
---

# Run API

Arguments: `$ARGUMENTS`

`dotnet run` never exits, so it always runs with `run_in_background: true`. (The `guard-bash` hook blocks a foreground one.)

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `ROOT`, `API_PROJECT`, `API_DIR`, `APP_HOST` and `HEALTH_URL`. If `HEALTH_URL` is empty, read `Properties/launchSettings.json` and `Program.cs` for the URL and the health route (`MapHealthChecks("...")`); if there is still none, you will poll the root URL instead and say so.

## Stop

If the arguments start with `stop`: for each `.claude/run-api/*.shell`, stop that background shell (use the harness's tool for stopping background tasks), then delete the file. Leave docker services running unless the user also said `infra`; then `docker compose stop`. **Never** `docker compose down -v`: it deletes the database volume. Report what was stopped, and stop here.

## Step 1: Pre-flight (in parallel)

- `dotnet --version`.
- `mkdir -p .claude/run-api`.
- If `.claude/run-api/api.shell` exists and its shell is still running, report the existing instance and stop. Never start a duplicate.
- Compose file present (`compose.yaml`, `docker-compose.yml`) and no `--no-infra`: `docker compose ps --format json` to see what is already up.

## Step 2: Infrastructure

**With an Aspire AppHost** (`APP_HOST` is set): skip this step and Step 3, and start the AppHost instead. It starts SQL Server (Docker or Podman must be running) and the API with the API's own launch profile, so `HEALTH_URL` is unchanged:

```bash
dotnet run --project <APP_HOST> --launch-profile https > .claude/run-api/api.log 2>&1
```

with `run_in_background: true`; save the shell id to `.claude/run-api/api.shell` and go on to Step 4. The first run pulls the SQL Server image, so allow up to 3 minutes (90 rounds) in Step 4. Report the dashboard URL as well: the AppHost prints `Login to the dashboard at <url>` in the log. Stopping the AppHost stops the API; the SQL Server container is persistent and keeps running, which is intended.

**Otherwise:** If services are down: `docker compose up -d` (always `-d`). Wait with a bounded loop rather than a blind sleep. Services with a healthcheck report `"Health":"starting"` until ready:

```bash
for i in $(seq 1 30); do docker compose ps --format json | grep -q '"Health":"starting"' || break; sleep 2; done
```

A database without a healthcheck reports ready immediately, so also probe it (for SQL Server, `docker compose exec <service> /opt/mssql-tools18/bin/sqlcmd ... -Q "SELECT 1"` with credentials from the compose file or user secrets) in the same bounded loop. If it is not ready after 60 s, show the last 30 lines of `docker compose logs <service>` and stop. If any service reports `"Health":"unhealthy"`, show its logs and stop.

## Step 3: Start the API

```bash
dotnet run --project <API_PROJECT> --launch-profile <profile> > .claude/run-api/api.log 2>&1
```

with `run_in_background: true`. Default the profile to the `https` profile in `launchSettings.json`, else the first one. Save the returned shell id to `.claude/run-api/api.shell`.

## Step 4: Wait for health

```bash
for i in $(seq 1 45); do curl -ksf -o /dev/null <HEALTH_URL> && break; sleep 2; done; curl -ks -o /dev/null -w '%{http_code}\n' <HEALTH_URL>
```

`-k` is only for `localhost` development certificates. If it never answers 200, show `tail -n 50 .claude/run-api/api.log` and report the startup error. Typical causes: the port in use, the database not ready, a missing user secret, or a DI error. A missing handler registration only fails when its endpoint is called, not at startup.

## Step 5: Report

```markdown
## API running
| | |
|---|---|
| URL | <base url> |
| Health | 200 (<n> s to ready) |
| OpenAPI | <base>/openapi/v1.json (or /scalar, /swagger) |
| Dashboard | <Aspire dashboard URL, when an AppHost runs> |
| Log | .claude/run-api/api.log |
| Shell | <id> (follow with Monitor) |
Next: smoke-health, or call the changed endpoints. Stop with `run-api stop`.
```

## Rules

- Never start a long-running process in the foreground.
- Never `docker compose down -v` or remove volumes.
- Never edit source, commit or push from this skill.
