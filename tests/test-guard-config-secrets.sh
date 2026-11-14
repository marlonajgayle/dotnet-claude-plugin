#!/usr/bin/env bash
# hooks/guard-config-secrets.sh: secrets stay out of appsettings*.json, and the block
# reason never repeats the secret.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dir="$T_TMP/src/Fixture.Api"

# write FILE CONTENT / edit FILE NEW_STRING / multiedit FILE NEW_STRING...
write() { run_hook guard-config-secrets.sh "$(jq -n --arg f "$dir/$1" --arg c "$2" '{tool_name: "Write", tool_input: {file_path: $f, content: $c}}')"; }
edit()  { run_hook guard-config-secrets.sh "$(jq -n --arg f "$dir/$1" --arg c "$2" '{tool_name: "Edit", tool_input: {file_path: $f, old_string: "\"\"", new_string: $c}}')"; }
multiedit() {
  local f="$1"; shift
  run_hook guard-config-secrets.sh "$(jq -n --arg f "$dir/$f" '{tool_name: "MultiEdit", tool_input: {file_path: $f, edits: [$ARGS.positional[] | {old_string: "x", new_string: .}]}}' --args "$@")"
}
blocks() { write "${3:-appsettings.json}" "$1"; expect_blocked "blocks: $1" "${2:-}"; }
allows() { write "${2:-appsettings.json}" "$1"; expect_allowed "allows: $1"; }

# Test values only. They are assembled from parts so that secret scanners leave this file alone.
jwt="eyJhbGciOiJIUzI1NiJ9"".eyJzdWIiOiIxMjM0NTY3ODkwIn0"".dBjftJeZ4CVPmB92K27uhbUJU1p1r"
aws="AKIA""IOSFODNN7EXAMPLE"
pem="-----BEGIN RSA PRIVATE"" KEY-----"

# --- blocked -------------------------------------------------------------------------------
blocks '{"Jwt": {"SecretKey": "hunter2-hunter2-hunter2"}}' 'key "SecretKey"'
blocks '{"Smtp": {"Password": "hunter2"}}' 'key "Password"'
blocks '{"Stripe": {"ApiKey": "sk_live_abcdef123456"}}' 'key "ApiKey"'
blocks '{"AzureAd": {"ClientSecret": "abc~DEF.123"}}' 'key "ClientSecret"'
blocks '{"ConnectionStrings": {"Default": "Server=sql;Database=Shop;User Id=sa;Password=hunter2;"}}' 'connection string "Default"'
blocks '{"ConnectionStrings": {"Default": "Server=sql;Database=Shop;Uid=sa;Pwd=hunter2"}}' 'connection string "Default"'
blocks '{"Storage": "DefaultEndpointsProtocol=https;AccountName=shop;AccountKey=abcdEFGH1234+/=="}' 'account key'
blocks "{\"Auth\": {\"Sample\": \"$jwt\"}}" 'a JWT'
blocks "{\"Signing\": {\"Pem\": \"$pem\"}}" 'a private key'
blocks "{\"Aws\": {\"Id\": \"$aws\"}}" 'an AWS access key'
blocks '{"Encryption": {"Material": "q83vEjRWeJCrze8BI0VniavN7wEjRWeJ"}}' 'a base64 key in "Material"'
blocks '{"Jwt": {"SecretKey": "hunter2-hunter2-hunter2"}}' '' appsettings.Development.json
blocks '{"Jwt": {"SecretKey": "hunter2-hunter2-hunter2"}}' '' appsettings.Production.json

edit appsettings.json '"Password": "hunter2"';                 expect_blocked 'blocks: a secret in an Edit new_string' 'key "Password"'
multiedit appsettings.json '"Port": "587"' '"Password": "hunter2"'; expect_blocked 'blocks: a secret in a later MultiEdit edit' 'key "Password"'

# The reason names the key, never the value.
write appsettings.json '{"Jwt": {"SecretKey": "hunter2-hunter2-hunter2"}, "ConnectionStrings": {"Default": "Server=sql;Password=s3cr3t-db-pass;"}}'
expect_blocked 'blocks: two secrets in one write' 'appsettings.json'
expect_lacks 'reason omits the key value' "$ERR" 'hunter2'
expect_lacks 'reason omits the connection string password' "$ERR" 's3cr3t-db-pass'
expect_contains 'reason points at user-secrets' "$ERR" 'user-secrets'

# --- allowed -------------------------------------------------------------------------------
allows '{"Jwt": {"SecretKey": ""}}'
allows '{"Jwt": {"SecretKey": "${JWT_SECRET}"}}'
allows '{"Jwt": {"SecretKey": "<set with dotnet user-secrets>"}}'
allows '{"Jwt": {"SecretKey": "__JWT_SECRET__"}}'
allows '{"Jwt": {"SecretKey": "#{JwtSecret}#"}}'
allows '{"Jwt": {"SecretKey": "{{ jwt_secret }}"}}'
allows '{"Jwt": {"Issuer": "https://shop.example.com", "Audience": "shop-api", "TokenLifetimeMinutes": "60"}}'
allows '{"KeyVault": {"Url": "https://shop-kv.vault.azure.net/"}}'
allows '{"Auth": {"TokenEndpoint": "https://login.example.com/token", "ApiKeyHeader": "X-Api-Key"}}'
allows '{"ConnectionStrings": {"Default": "Server=localhost;Database=Shop;Trusted_Connection=True;"}}'
allows '{"ConnectionStrings": {"Default": "Server=sql;Database=Shop;User Id=sa;Password=${DB_PASSWORD};"}}'
allows '{"Logging": {"LogLevel": {"Default": "Information"}}, "AllowedHosts": "*"}'
# appsettings.Local.json is the one tolerated place.
allows '{"Jwt": {"SecretKey": "hunter2-hunter2-hunter2"}}' appsettings.Local.json

# --- beyond appsettings ----------------------------------------------------------------------
blocks '{"profiles": {"https": {"environmentVariables": {"Jwt__SecretKey": "hunter2-hunter2-hunter2"}}}}' 'key "Jwt__SecretKey"' Properties/launchSettings.json
allows '{"profiles": {"https": {"environmentVariables": {"ASPNETCORE_ENVIRONMENT": "Local"}}}}' Properties/launchSettings.json

blocks 'STRIPE_API_KEY=sk_live_abcdef123456' 'variable "STRIPE_API_KEY"' .env
blocks 'export DB_PASSWORD="hunter2"' 'variable "DB_PASSWORD"' .env.production
blocks "JWT_SIGNING_KEY='q83vEjRWeJCrze8BI0VniavN7wEjRWeJ'" 'JWT_SIGNING_KEY' .env
blocks 'DATABASE_URL=Server=sql;Database=Shop;User Id=sa;Password=hunter2' 'connection string' .env
allows 'STRIPE_API_KEY=' .env.example
allows 'STRIPE_API_KEY=<your key>' .env.example
allows 'DB_PASSWORD=${DB_PASSWORD}' .env
allows 'ASPNETCORE_ENVIRONMENT=Local' .env
allows 'TOKEN_LIFETIME=60' .env.example
allows 'GOOGLE_CREDENTIALS_FILE=./creds.json' .env.example
blocks 'GITHUB_TOKEN=ghp_abcdef1234567890' 'GITHUB_TOKEN' .env

blocks '<Project><PropertyGroup><NuGetApiKey>oy2abcdef1234567890</NuGetApiKey></PropertyGroup></Project>' 'property <NuGetApiKey>' Directory.Build.props
blocks '<Project><PropertyGroup><DbConn>Server=sql;User Id=sa;Password=hunter2</DbConn></PropertyGroup></Project>' 'connection string' Fixture.Api.csproj
allows '<Project><PropertyGroup><UserSecretsId>0f1e2d3c-aaaa-bbbb-cccc-1234567890ab</UserSecretsId></PropertyGroup></Project>' Fixture.Api.csproj
allows '<Project><PropertyGroup><NuGetApiKey>$(NUGET_API_KEY)</NuGetApiKey></PropertyGroup></Project>' Directory.Build.props

blocks 'var secretKey = "hunter2-hunter2-hunter2";' 'string literal assigned to "secretKey"' Program.cs
blocks 'private const string ApiKey = "sk_live_abcdef123456";' 'ApiKey' Infrastructure/Payments/Stripe.cs
blocks 'options.UseSqlServer("Server=sql;Database=Shop;User Id=sa;Password=hunter2");' 'connection string' Program.cs
blocks 'var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("my-super-secret-signing-key-123"));' 'signing key' Program.cs
blocks "var token = \"$jwt\";" 'a JWT' Program.cs
allows 'var password = request.Password;' Program.cs
allows 'public string Password { get; init; } = string.Empty;' Features/Users/Register.cs
allows 'RuleFor(x => x.Password).MinimumLength(12).WithMessage("Password must be 12 characters or more.");' Features/Users/RegisterValidator.cs
allows 'const string PasswordResetTokenPurpose = "ResetPassword";' Infrastructure/Auth/Tokens.cs
allows 'var secretKey = builder.Configuration["Jwt:SecretKey"];' Program.cs
allows 'options.Password.RequiredLength = 12;' Program.cs

# Test projects and migrations carry fake credentials on purpose.
run_hook guard-config-secrets.sh "$(jq -n --arg f "$T_TMP/tests/Fixture.Api.IntegrationTests/ApiFactory.cs" '{tool_name: "Write", tool_input: {file_path: $f, content: "var password = \"Your_password123\";"}}')"
expect_allowed 'allows: a password in a test project'
run_hook guard-config-secrets.sh "$(jq -n --arg f "$T_TMP/src/Fixture.Api.Tests/Seed.cs" '{tool_name: "Write", tool_input: {file_path: $f, content: "var password = \"Your_password123\";"}}')"
expect_allowed 'allows: a password in a *.Tests project folder'

# A file git ignores is never committed: the .env that init-project writes, for example.
ignored="$T_TMP/ignored"; t_repo "$ignored"; echo '.env' > "$ignored/.gitignore"
run_hook guard-config-secrets.sh "$(jq -n --arg f "$ignored/.env" '{tool_name: "Write", tool_input: {file_path: $f, content: "MSSQL_SA_PASSWORD=hunter2hunter2"}}')"
expect_allowed 'allows: a secret in a git-ignored file'
run_hook guard-config-secrets.sh "$(jq -n --arg f "$ignored/.env.example" '{tool_name: "Write", tool_input: {file_path: $f, content: "MSSQL_SA_PASSWORD=hunter2hunter2"}}')"
expect_blocked 'blocks: the same secret in a committed .env.example' 'MSSQL_SA_PASSWORD'

# Other files are not this hook's business.
allows 'Password=hunter2' notes.txt

run_hook guard-config-secrets.sh '{"tool_name":"Write","tool_input":{}}'; expect_allowed 'allows: payload without a file path'
run_hook guard-config-secrets.sh '';                                     expect_allowed 'allows: empty payload'

t_done
