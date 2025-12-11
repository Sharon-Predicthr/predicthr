using Microsoft.EntityFrameworkCore;
using predicthrAPI.Data;

var builder = WebApplication.CreateBuilder(args);

// -----------------------------------------------------------
// 1️⃣  Load active connection (Local / Docker)
// -----------------------------------------------------------
var activeConnection = builder.Configuration.GetValue<string>("ActiveConnection");
var connectionString = builder.Configuration.GetConnectionString(activeConnection);

// -----------------------------------------------------------
// 2️⃣  Add CORS for Frontend (React / Angular / etc.)
// -----------------------------------------------------------
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        policy.WithOrigins(
            "http://localhost:3000",
            "http://localhost:4200",
            "http://localhost:5173",
            " https://nonclose-pesticidal-elle.ngrok-free.dev",
            "https://your-frontend.com"
        )
        .AllowAnyHeader()
        .AllowAnyMethod()
        .AllowCredentials();
    });
});

// -----------------------------------------------------------
// 3️⃣ Add Controllers & Swagger
// -----------------------------------------------------------
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// -----------------------------------------------------------
// 4️⃣  Add DB Context (now uses dynamic connection)
// -----------------------------------------------------------
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));

var app = builder.Build();

// -----------------------------------------------------------
// 5️⃣  Configure Middleware
// -----------------------------------------------------------
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

// ⭐ Enable CORS BEFORE routing
app.UseCors("AllowFrontend");

app.UseAuthorization();

app.MapControllers();

app.Run();
