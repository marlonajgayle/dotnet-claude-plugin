# dotnet-claude-plugin
Claude Code plugin marketplace with an agentic harness for .NET 10 projects. Ships slash commands, review and security subagents, guardrail hooks, MCP servers, and skills that enforce Domain-Driven Design with Vertical Slice Architecture, so Claude builds ASP.NET Core, Blazor, and Azure apps the way your team does.

## Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- Roslyn Language Server, which gives Claude C# diagnostics after edits and symbol navigation:

  ```sh
  dotnet tool install --global roslyn-language-server --prerelease
  ```

  Make sure `~/.dotnet/tools` is on the `PATH` of the shell you launch `claude` from.
