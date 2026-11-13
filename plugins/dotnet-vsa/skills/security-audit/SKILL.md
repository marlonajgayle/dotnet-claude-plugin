---
name: security-audit
description: "Read-only six-layer security audit of a .NET application: vulnerable and deprecated NuGet packages, secrets in config, OWASP code patterns, authentication and authorization configuration (including per-endpoint policies and IDOR on owner-scoped routes), CORS, and data protection. Writes a severity-rated report with remediation to .claude/security-audits/<timestamp>.md. Use when the user says: security audit, security scan, check for vulnerabilities, find secrets, OWASP, auth review, CORS check, CVE check, hardcoded password, security posture."
---

# Security Audit

Read-only. Do not edit source or commit. The only file you write is the report.

- **Redact secrets**: first four characters, `…`, last two (`a9F3…0U`). Never paste a full secret into the report or chat.
- **Cite** every finding as `[file:LN](path#LLN)`.
- **Honest coverage**: if a tool or the network is unavailable, record an Info finding and continue.
- Severity: **Critical** exploitable now or publicly exposed; **High** exploitable with modest effort; **Medium** broadens the blast radius; **Low** defence in depth; **Info** observation.

## Phase 0: Discovery

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Glob all `*.sln`/`*.csproj` and every `Program.cs`. `mkdir -p .claude/security-audits`; the report is `.claude/security-audits/<YYYY-MM-DD-HHMM>.md`. Say in one line that the audit is starting and where the report will go.

## Layer 1: Packages

`dotnet list <SLN> package --vulnerable --include-transitive`, then `--deprecated`, then `--outdated`. One finding per vulnerable row, mapping the advisory severity directly (Moderate is Medium). Remediation: `dotnet add package <Name> --version <fixed>` plus the advisory URL. (`package-health` is the quick standalone version of this layer.)

## Layer 2: Secrets

Files: `appsettings*.json`, `.env*`, `secrets.json`, `*.config`, `launchSettings.json`, `*.yml`/`*.yaml`, excluding `bin`, `obj`, `node_modules`, `.git`.

| Pattern | Example |
|---|---|
| `"(SecretKey\|ApiKey\|ClientSecret\|Password\|Pwd\|Token)"\s*:\s*"[^"$]{8,}"` | a populated key |
| `eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}` | JWT |
| `AKIA[0-9A-Z]{16}` | AWS key |
| `-----BEGIN [A-Z ]*PRIVATE KEY-----` | PEM |
| `(Password\|Pwd)=[^;"]+`, `AccountKey=`, `SharedAccessKey=` | connection strings |

Severity by file: Production/Stage config Critical; Development High; `appsettings.Local.json`/`secrets.json` Medium; `.env*` Critical (Info for `.env.example`). Also check whether values in `appsettings.Local.json` were copied into other profiles. Remediation: `dotnet user-secrets set`, environment variables or Key Vault, and **rotate** the leaked value.

## Layer 3: OWASP code patterns

Over `*.cs`, `*.cshtml`, `*.razor` (excluding `Migrations/`):

- A03 Injection: `FromSqlRaw(`/`ExecuteSqlRaw(` with `$` or `+`; `new SqlCommand(` built by concatenation; `Process.Start(` with concatenation. Critical when request input reaches it.
- A03 XSS: `@Html.Raw(`; `(MarkupString)` over user input. High.
- A02 Crypto: `MD5`, `SHA1`, `DES`, `RC2`, `TripleDES`; `new Random(` in security, token or password code. High.
- A08 Deserialisation: `BinaryFormatter`, `NetDataContractSerializer`, `LosFormatter`. Critical.
- A05 Misconfiguration: `UseDeveloperExceptionPage()` outside a development check (Medium); `EnableSensitiveDataLogging()` outside the local branch (High); debug endpoints mapped in `Program.cs` (`/test-*`, `/send-email`, `/debug`) without an environment guard (High).
- A01 Broken access control: run `bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --no-build`. Every endpoint-auth FAIL is High (Critical when the route returns personal data). Then apply the `audit-authorization` IDOR rule: a route carrying an owner id (`{userId}`, `{customerId}`, `{accountId}`…) under a policy that only requires authentication, with no ownership check in the handler, is Critical.

## Layer 4: Authentication configuration

Read `Program.cs` and files matching `*Identity*`, `*Auth*`, `*Jwt*`, `AuthorizationPolicies.cs`.

| Setting | Expected | If not |
|---|---|---|
| `ValidateIssuer`, `ValidateAudience`, `ValidateLifetime`, `ValidateIssuerSigningKey` | `true` | Critical |
| `ClockSkew` | ≤ 5 min | Medium |
| `RequireHttpsMetadata` | `true` outside development | High |
| HS256 signing key | ≥ 32 bytes, from configuration | High |
| `RequireConfirmedEmail`/`Account` | `true` | Medium |
| `Lockout.MaxFailedAccessAttempts` | ≤ 10 | Medium |
| `Password.RequiredLength` | ≥ 8 (12 better) | Medium |
| Cookies | `HttpOnly`, `Secure`, `SameSite=Lax/Strict` | High / High / Medium |
| Access-token lifetime vs refresh | short access token with a working refresh path | Info |

Quote the offending line in each finding.

## Layer 5: CORS

Grep `AddCors|UseCors|WithOrigins|AllowAnyOrigin|AllowCredentials|SetIsOriginAllowed`.

- `AllowAnyOrigin()` with `AllowCredentials()`, or `SetIsOriginAllowed(_ => true)`: Critical.
- `AllowAnyOrigin()` alone: Medium.
- No CORS at all: Info for server-to-server or native-mobile clients; Medium when a browser client (Blazor WASM, SPA) calls the API from another origin.
- Note that `AllowedHosts: "*"` is host filtering, not CORS.

## Layer 6: Data protection

- Encryption services: AES-CBC without an HMAC or GCM is High; a static IV Critical; a hard-coded key Critical; a key from configuration without Key Vault in production Medium.
- `UseHsts()` and `UseHttpsRedirection()` missing: Medium.
- Security headers (CSP Medium; `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` Low).
- Logging: a Serilog filter or destructuring policy that drops `password`/`token`/`secret` properties; absent is Info.

## Report

```markdown
# Security Audit — <project> — <timestamp>
## Executive summary
Critical N · High N · Medium N · Low N · Info N
### Top risks
1. **[CRITICAL]** … — [file:LN](...)
## Layer 1: Vulnerable packages
### [SEVERITY] <title>
- **Location** · **What** · **Why it matters** · **Remediation** · **Reference**
… Layers 2–6 in the same format (Layer 3 tags the OWASP category).
## Coverage notes
Tools and versions, skipped checks and why, files scanned.
```

## Chat summary

Counts per severity, the top three findings with links, and the report path. Remediation stays in the report. Never commit the report.
