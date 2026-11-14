using DvsaTemplate.Api.Infrastructure.Authorization;
using DvsaTemplate.Api.Infrastructure.Endpoints;
using DvsaTemplate.Api.Infrastructure.Outbox;
using DvsaTemplate.Api.Infrastructure.Persistence;
using DvsaTemplate.Api.Infrastructure.RateLimiting;
using FluentValidation;

var builder = WebApplication.CreateBuilder(args);

// The Local environment (launchSettings.json) is for running against the docker compose
// database. User secrets load only in Development by default, so load them here too: they hold
// the signing key that `dotnet user-jwts` uses for local tokens.
if (builder.Environment.IsEnvironment("Local"))
{
    builder.Configuration.AddUserSecrets<Program>(optional: true);
}

builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<ICurrentUser, CurrentUser>();

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddScoped<IApplicationDbContext>(sp => sp.GetRequiredService<ApplicationDbContext>());

builder.Services.AddAuthentication().AddJwtBearer();
builder.Services.AddAppAuthorization();
builder.Services.AddAppRateLimiting(builder.Configuration);
builder.Services.AddValidatorsFromAssemblyContaining<Program>(includeInternalTypes: true);
builder.Services.AddEndpoints(typeof(Program).Assembly);
builder.Services.AddHostedService<OutboxProcessor>();

// Feature handlers. Register every handler here, one block per feature, so it resolves at
// runtime: builder.Services.AddScoped<CreateOrderHandler>(); (the register-handler skill adds them)

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment() || app.Environment.IsEnvironment("Local"))
{
    app.MapOpenApi();
}
else
{
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapHealthChecks("/health");
app.MapEndpoints();

app.Run();

// Lets integration tests reach the entry point through WebApplicationFactory<Program>.
public partial class Program;
