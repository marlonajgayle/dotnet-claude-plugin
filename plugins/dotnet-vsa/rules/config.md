---
paths:
  - "**/appsettings*.json"
---

# Application settings

- **No secrets in `appsettings*.json`.** That covers passwords, API keys, client secrets, signing keys, tokens, and connection strings with a password or account key. A hook blocks the write. Leave the value empty or use a placeholder such as `${JWT_SECRET}`.
- Secrets go in user-secrets (`dotnet user-secrets set "Section:Key" "value"`), environment variables or Key Vault.
- `appsettings.Local.json` is the one tolerated exception, for local development only. Never copy its values into the Development, Stage or Production files, and never commit it if the repository ignores it.
- If a real secret has already been written to a tracked file, say so: it must be rotated, not only removed.
