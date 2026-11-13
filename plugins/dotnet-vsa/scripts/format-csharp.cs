// PostToolUse hook: runs `dotnet format` on a C# file after Claude writes or edits it.
// Reads the hook payload from stdin and formats only the file in tool_input.file_path,
// using the nearest .csproj so .editorconfig style and analyzer fixes apply.
// Exit 0 = formatted or nothing to do; exit 2 = formatting failed (stderr is shown to Claude).
#:property PublishAot=false

using System.Diagnostics;
using System.Text.Json;

string? filePath;
try
{
    using var payload = JsonDocument.Parse(Console.In.ReadToEnd());
    filePath = payload.RootElement.TryGetProperty("tool_input", out var input)
        && input.TryGetProperty("file_path", out var fp)
        ? fp.GetString()
        : null;
}
catch (JsonException)
{
    return 0;
}

if (string.IsNullOrEmpty(filePath)
    || !filePath.EndsWith(".cs", StringComparison.OrdinalIgnoreCase)
    || !File.Exists(filePath))
{
    return 0;
}

filePath = Path.GetFullPath(filePath);
var project = FindNearestProject(Path.GetDirectoryName(filePath)!);

// With a project: full format (whitespace, code style, analyzers).
// Without one (loose .cs file): whitespace-only formatting of the folder.
var workDir = project is not null ? Path.GetDirectoryName(project)! : Path.GetDirectoryName(filePath)!;
string[] formatArgs = project is not null
    ? ["format", project, "--include", Path.GetRelativePath(workDir, filePath)]
    : ["format", "whitespace", "--folder", workDir, "--include", Path.GetFileName(filePath)];

var psi = new ProcessStartInfo("dotnet")
{
    WorkingDirectory = workDir,
    RedirectStandardOutput = true,
    RedirectStandardError = true,
};
foreach (var a in formatArgs) psi.ArgumentList.Add(a);

using var proc = Process.Start(psi)!;
var stdout = proc.StandardOutput.ReadToEndAsync();
var stderr = proc.StandardError.ReadToEndAsync();
proc.WaitForExit();

if (proc.ExitCode != 0)
{
    Console.Error.WriteLine($"dotnet format failed for {filePath} (exit {proc.ExitCode}):");
    Console.Error.WriteLine((await stderr).Trim() is { Length: > 0 } err ? err : (await stdout).Trim());
    return 2;
}

return 0;

static string? FindNearestProject(string dir)
{
    for (var d = new DirectoryInfo(dir); d is not null; d = d.Parent)
    {
        var projects = d.GetFiles("*.csproj");
        if (projects.Length > 0) return projects[0].FullName;
    }
    return null;
}
