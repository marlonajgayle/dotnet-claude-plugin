#!/usr/bin/env bash
# End-to-end check of the init-project, write-handler-tests and write-integration-tests templates:
# scaffold a new app, add the packages the skills add, build it, add a sample slice (an
# owner-scoped Notes entity that raises an event), check that every convention check passes, run
# handler tests on SQLite from the handler-test templates, then create the integration test project
# from its templates and run its tests against SQL Server in a container. Last, scaffold the
# --aspire variant and build it.
#
# Needs the .NET 10 SDK, network access to nuget.org and, for the last step, Docker. Not part of
# tests/run.sh, which needs neither.
#
# Usage: tests/e2e/run.sh [--keep] [--no-docker] [--no-aspire]
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$(cd "$here/../../plugins/dotnet-vsa" && pwd)"
keep=0; docker=1; aspire=1
for a in "$@"; do case "$a" in --keep) keep=1 ;; --no-docker) docker=0 ;; --no-aspire) aspire=0 ;; *) echo "unknown option $a" >&2; exit 64 ;; esac; done

step() { printf '\n== %s\n' "$*"; }
fail() { echo "e2e: FAIL: $*" >&2; exit 1; }

# Discovery skips projects whose path contains "test", so the work directory must not.
work="$(cd "$(mktemp -d /tmp/dvsa-e2e.XXXXXX)" && pwd -P)"   # macOS: /tmp is a symlink
[ "$keep" = 1 ] && echo "keeping $work" || trap 'rm -rf "${work:?}"' EXIT
app=E2eShop; api="$work/src/$app.Api"
cd "$work"
git init -q && git symbolic-ref HEAD refs/heads/main

step "scaffold"
bash "$plugin/skills/init-project/scaffold.sh" "$work" "$app" > /dev/null
! grep -rq DvsaTemplate "$work" --exclude-dir=.git || fail "template token left in the output"

step "packages (Microsoft.* pinned to 10.x)"
v() { bash "$plugin/scripts/nuget-version.sh" "$@"; }
for p in Microsoft.EntityFrameworkCore.SqlServer Microsoft.EntityFrameworkCore.Design \
         Microsoft.AspNetCore.Authentication.JwtBearer Microsoft.AspNetCore.OpenApi; do
  (cd "$api" && dotnet add package "$p" --version "$(v "$p" 10)" > /dev/null)
done
(cd "$api" && dotnet add package FluentValidation.DependencyInjectionExtensions --version "$(v FluentValidation.DependencyInjectionExtensions)" > /dev/null)

step "build the empty project"
dotnet build "$app.slnx" -nologo -v q
bash "$plugin/scripts/verify-conventions.sh" --root "$work" --no-build | tail -n 1

step "add the sample slice"
mkdir -p "$api/Domain/Notes" "$api/Features/Notes"
for f in Domain/Notes/Note.cs Features/Notes/CreateNote.cs Features/Notes/GetNote.cs Features/Notes/DeleteNote.cs; do
  sed "s/E2eShop/$app/g" "$here/sample/src/Api/$f" > "$api/$f"
done
sed "s/E2eShop/$app/g" "$here/sample/src/Api/NoteConfiguration.cs" > "$api/Infrastructure/Persistence/Configurations/NoteConfiguration.cs"
# The edits add-entity, register-handler and add-domain-event make.
perl -0pi -e "s/(using $app\.Api\.Infrastructure\.Outbox;)/using $app.Api.Domain.Notes;\n\$1/; s/(    public DbSet<OutboxMessage>)/    public DbSet<Note> Notes => Set<Note>();\n\n\$1/" "$api/Infrastructure/Persistence/ApplicationDbContext.cs"
perl -0pi -e "s/(using $app\.Api\.Infrastructure\.Outbox;)/using $app.Api.Domain.Notes;\n\$1/; s/(    DbSet<OutboxMessage>)/    DbSet<Note> Notes { get; }\n\n\$1/" "$api/Infrastructure/Persistence/IApplicationDbContext.cs"
perl -0pi -e "s/^(namespace )/using System.Text.Json;\nusing $app.Api.Domain.Notes;\nusing $app.Api.Features.Notes.CreateNote;\n\n\$1/m; s|        // Dispatch branches go here, before the final return.\n\n        await Task.CompletedTask;\n|        if (message.Type == nameof(NoteCreated))\n        {\n            var domainEvent = JsonSerializer.Deserialize<NoteCreated>(message.Payload)!;\n            await services.GetRequiredService<NoteCreatedHandler>().HandleAsync(domainEvent, cancellationToken);\n            return true;\n        }\n\n|" "$api/Infrastructure/Outbox/OutboxDispatcher.cs"
perl -0pi -e "s/(using FluentValidation;)/\$1\nusing $app.Api.Features.Notes.CreateNote;\nusing $app.Api.Features.Notes.DeleteNote;\nusing $app.Api.Features.Notes.GetNote;/; s/(\(the register-handler skill adds them\)\n)/\$1\n\/\/ Notes\nbuilder.Services.AddScoped<CreateNoteHandler>();\nbuilder.Services.AddScoped<GetNoteHandler>();\nbuilder.Services.AddScoped<DeleteNoteHandler>();\nbuilder.Services.AddScoped<NoteCreatedHandler>();\n/" "$api/Program.cs"
grep -q 'nameof(NoteCreated)' "$api/Infrastructure/Outbox/OutboxDispatcher.cs" || fail "dispatch branch was not added"
grep -q 'AddScoped<NoteCreatedHandler>' "$api/Program.cs" || fail "handlers were not registered"

step "build and verify the slice"
dotnet build "$app.slnx" -nologo -v q
report="$(bash "$plugin/scripts/verify-conventions.sh" --root "$work" --no-build)" || { echo "$report"; fail "convention checks failed on the sample"; }
echo "$report" | tail -n 1
echo "$report" | grep -q '^- WARN' && { echo "$report"; fail "convention warnings on the sample"; }

step "handler tests on SQLite from the write-handler-tests templates"
unit="$work/tests/$app.Api.Tests"
dotnet new xunit -n "$app.Api.Tests" -o "$unit" > /dev/null
rm "$unit/UnitTest1.cs"
(cd "$unit" && dotnet add package Microsoft.EntityFrameworkCore.Sqlite --version "$(v Microsoft.EntityFrameworkCore.Sqlite 10)" > /dev/null \
  && dotnet add reference "../../src/$app.Api/$app.Api.csproj" > /dev/null)
dotnet sln "$app.slnx" add "$unit/$app.Api.Tests.csproj" > /dev/null
mkdir -p "$unit/Infrastructure" "$unit/Features/Notes"
for f in SqliteDbContextFactory.cs TestDoubles.cs; do
  sed "s/DvsaTemplate/$app/g" "$plugin/skills/write-handler-tests/templates/$f" > "$unit/Infrastructure/$f"
done
sed "s/E2eShop/$app/g" "$here/sample/tests/NotesHandlerTests.cs" > "$unit/Features/Notes/NotesHandlerTests.cs"
dotnet build "$app.slnx" -nologo -v q
dotnet test "$unit/$app.Api.Tests.csproj" -nologo -v q

step "integration test project from the templates"
tests="$work/tests/$app.Api.IntegrationTests"
dotnet new xunit -n "$app.Api.IntegrationTests" -o "$tests" > /dev/null
rm "$tests/UnitTest1.cs"
(cd "$tests" && dotnet add package Microsoft.AspNetCore.Mvc.Testing --version "$(v Microsoft.AspNetCore.Mvc.Testing 10)" > /dev/null \
  && dotnet add package Testcontainers.MsSql --version "$(v Testcontainers.MsSql)" > /dev/null \
  && dotnet add reference "../../src/$app.Api/$app.Api.csproj" > /dev/null)
dotnet sln "$app.slnx" add "$tests/$app.Api.IntegrationTests.csproj" > /dev/null
mkdir -p "$tests/Infrastructure" "$tests/Features/Notes"
for f in ApiFactory.cs TestAuthHandler.cs; do
  sed "s/DvsaTemplate/$app/g" "$plugin/skills/write-integration-tests/templates/$f" > "$tests/Infrastructure/$f"
done
sed "s/E2eShop/$app/g" "$here/sample/tests/NotesEndpointTests.cs" > "$tests/Features/Notes/NotesEndpointTests.cs"
dotnet build "$app.slnx" -nologo -v q

if [ "$docker" = 0 ]; then
  step "skipping the integration tests (--no-docker)"
else
  step "integration tests against SQL Server in a container"
  docker info > /dev/null 2>&1 || fail "Docker is not running (use --no-docker to skip this step)"
  dotnet test "$app.slnx" -nologo -v q --filter "Category=Integration"
fi

if [ "$aspire" = 1 ]; then
  step "the --aspire variant: scaffold, packages, build"
  aw="$(cd "$(mktemp -d /tmp/dvsa-e2e-aspire.XXXXXX)" && pwd -P)"
  [ "$keep" = 1 ] && echo "keeping $aw" || trap 'rm -rf "${work:?}" "${aw:?}"' EXIT
  (cd "$aw" && git init -q)
  aspire_version="$(v Aspire.AppHost.Sdk)"
  bash "$plugin/skills/init-project/scaffold.sh" "$aw" "$app" --aspire "$aspire_version" > /dev/null
  aapi="$aw/src/$app.Api"; adef="$aw/src/$app.ServiceDefaults"; ahost="$aw/src/$app.AppHost"
  for p in Microsoft.EntityFrameworkCore.SqlServer Microsoft.EntityFrameworkCore.Design \
           Microsoft.AspNetCore.Authentication.JwtBearer Microsoft.AspNetCore.OpenApi; do
    (cd "$aapi" && dotnet add package "$p" --version "$(v "$p" 10)" > /dev/null)
  done
  (cd "$aapi" && dotnet add package FluentValidation.DependencyInjectionExtensions --version "$(v FluentValidation.DependencyInjectionExtensions)" > /dev/null)
  for p in Microsoft.Extensions.Http.Resilience Microsoft.Extensions.ServiceDiscovery; do
    (cd "$adef" && dotnet add package "$p" --version "$(v "$p" 10)" > /dev/null)
  done
  for p in OpenTelemetry.Exporter.OpenTelemetryProtocol OpenTelemetry.Extensions.Hosting OpenTelemetry.Instrumentation.AspNetCore \
           OpenTelemetry.Instrumentation.Http OpenTelemetry.Instrumentation.Runtime; do
    (cd "$adef" && dotnet add package "$p" --version "$(v "$p")" > /dev/null)
  done
  (cd "$ahost" && dotnet add package Aspire.Hosting.SqlServer --version "$aspire_version" > /dev/null)
  dotnet build "$aw/$app.slnx" -nologo -v q
  bash "$plugin/scripts/verify-conventions.sh" --root "$aw" --no-build | tail -n 1
fi

step "e2e passed"
