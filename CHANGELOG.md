# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When cutting a release, rename `[Unreleased]` to the new version and date, and
bump `version` in both `.claude-plugin/marketplace.json` and
`plugins/dotnet/.claude-plugin/plugin.json` to match. Installed users stay on
the pinned version until it changes.

## [Unreleased]

Targets `0.1.0`.

### Added

- Marketplace manifest (`.claude-plugin/marketplace.json`) listing the `dotnet` plugin.
- `dotnet` plugin scaffold: manifest, `commands/`, `agents/`, `skills/`, `hooks/hooks.json`, `scripts/`, and `.mcp.json`.
- Roslyn Language Server integration (`.lsp.json`) for `.cs` files, giving Claude C# diagnostics after edits and symbol navigation. Requires `dotnet tool install --global roslyn-language-server --prerelease`.
- README prerequisites for the .NET 10 SDK and the Roslyn Language Server.

[Unreleased]: https://github.com/marlonajgayle/dotnet-claude-plugin/commits/main
