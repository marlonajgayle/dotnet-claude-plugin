var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRateLimiter(options => { });

// Orders
builder.Services.AddScoped<CreateOrderHandler>();
builder.Services.AddScoped<ListOrdersHandler>();
builder.Services.AddTransient<GetOrderHandler>();

var app = builder.Build();
app.Run();
