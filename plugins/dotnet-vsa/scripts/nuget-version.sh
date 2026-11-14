#!/usr/bin/env bash
# Prints the newest stable version of a NuGet package, optionally within one major version.
# Microsoft.AspNetCore.* and Microsoft.EntityFrameworkCore.* packages must match the project's
# target framework (10.x for net10.0): a bare `dotnet add package` picks the newest major, which
# may target a newer .NET and fail to restore or build.
#
# Usage: nuget-version.sh <PackageId> [major]
# Exit 0 and prints the version; exit 1 when the package or a matching version is not found.
set -u
[ $# -ge 1 ] || { echo "usage: nuget-version.sh <PackageId> [major]" >&2; exit 64; }
id="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
major="${2:-}"
command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "nuget-version: needs curl and jq" >&2; exit 1; }

versions="$(curl -fsSL --max-time 20 "https://api.nuget.org/v3-flatcontainer/$id/index.json" 2>/dev/null)" \
  || { echo "nuget-version: $1 not found on nuget.org (or no network)" >&2; exit 1; }
v="$(printf '%s' "$versions" | jq -r --arg m "$major" '
  [.versions[] | select(contains("-") | not) | select($m == "" or startswith($m + "."))] | last // empty')"
[ -n "$v" ] || { echo "nuget-version: no stable ${major:+$major.x }version of $1" >&2; exit 1; }
printf '%s\n' "$v"
