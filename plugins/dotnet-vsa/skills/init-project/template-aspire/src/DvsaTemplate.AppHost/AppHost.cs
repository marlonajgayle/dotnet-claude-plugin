// Runs the API and its SQL Server together for local development, with the Aspire dashboard for
// logs, traces and metrics. Start it in the background (the run-api skill does this):
//   dotnet run --project src/DvsaTemplate.AppHost
// Needs Docker or Podman for the SQL Server container. Aspire generates the sa password and keeps
// it in this project's user secrets (Parameters:sql-password).
var builder = DistributedApplication.CreateBuilder(args);

// The data volume and persistent lifetime keep the database between runs, like compose.yaml would.
var sql = builder.AddSqlServer("sql")
    .WithDataVolume()
    .WithLifetime(ContainerLifetime.Persistent);

// The API reads ConnectionStrings:Default; configuration keys are case-insensitive, so the
// "default" database resource supplies it.
var database = sql.AddDatabase("default", databaseName: "__DB_NAME__");

builder.AddProject<Projects.DvsaTemplateIdent_Api>("api")
    .WithReference(database)
    .WaitFor(database);

builder.Build().Run();
