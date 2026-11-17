using System.Net;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using TapMyPC.Api.Contracts;
using TapMyPC.Core.Devices;
using TapMyPC.Core.Timers;

namespace TapMyPC.Api;

public static class ApiHost
{
    public static async Task<WebApplication> StartAsync(IPAddress address, int port, X509Certificate2 certificate,
        IDeviceController device, PairingService pairing, PowerScheduler scheduler, CancellationToken cancellationToken = default)
    {
        var builder = WebApplication.CreateSlimBuilder(new WebApplicationOptions { Args = [], ApplicationName = typeof(ApiHost).Assembly.FullName });
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.AddServerHeader = false;
            options.Limits.MaxRequestBodySize = 4096;
            options.Listen(address, port, listener => listener.UseHttps(certificate));
        });
        builder.Services.ConfigureHttpJsonOptions(options => options.SerializerOptions.Converters.Add(new JsonStringEnumConverter(allowIntegerValues: false)));
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = 429;
            options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
                RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ =>
                    new FixedWindowRateLimiterOptions { PermitLimit = 120, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
        });
        var app = builder.Build();
        var commands = new RemoteCommands(device, scheduler.Activity);
        app.Use(async (context, next) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers["X-Content-Type-Options"] = "nosniff";
            context.Response.Headers["Referrer-Policy"] = "no-referrer";
            context.Response.Headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; form-action 'self'";
            // Prevent cross-site browser requests and DNS-rebinding Host values. Native clients can omit Origin.
            var host = context.Request.Host.Host;
            if (host != address.ToString() && !(IPAddress.IsLoopback(address) && host == "localhost"))
            { context.Response.StatusCode = 400; return; }
            var origin = context.Request.Headers.Origin.ToString();
            if (origin.Length > 0 && origin != $"https://{context.Request.Host}")
            { context.Response.StatusCode = 403; return; }
            try { await next(); }
            catch (Exception ex) when (!context.Response.HasStarted)
            {
                var status = ex switch
                {
                    UnauthorizedAccessException => 401,
                    ArgumentException or BadHttpRequestException => 400,
                    NotSupportedException => 422,
                    InvalidOperationException => 409,
                    _ => 500
                };
                context.Response.StatusCode = status;
                await context.Response.WriteAsJsonAsync(new { error = status == 500 ? "Windows could not complete this command. Check the PC and try again." : ex.Message });
            }
        });
        app.UseRateLimiter();
        app.Use(async (context, next) =>
        {
            if (context.Request.Path.StartsWithSegments("/api") && context.Request.Path != "/api/v1/pair")
            {
                var auth = context.Request.Headers.Authorization.ToString();
                if (!auth.StartsWith("Bearer ", StringComparison.Ordinal) || !pairing.Authorize(auth[7..]))
                { context.Response.StatusCode = 401; await context.Response.WriteAsJsonAsync(new { error = "Pair this device with the PC." }); return; }
            }
            await next();
        });
        foreach (var (path, file, contentType) in new[] { ("/", "index.html", "text/html"), ("/app.js", "app.js", "text/javascript"), ("/styles.css", "styles.css", "text/css") })
        {
            app.MapGet(path, async context =>
            {
                context.Response.ContentType = contentType;
                await using var stream = typeof(ApiHost).Assembly.GetManifestResourceStream($"TapMyPC.Api.wwwroot.{file}")!;
                await stream.CopyToAsync(context.Response.Body, context.RequestAborted);
            });
        }
        app.MapPost("/api/v1/pair", (PairRequest request) =>
            Results.Ok(new { token = pairing.Pair(request.Code ?? "", request.Name ?? "") }));
        app.MapGet("/api/v1/status", () =>
        {
            var capabilities = device.Capabilities;
            AudioState? audio = null;
            try { if (capabilities.Audio) audio = device.ReadAudio(); } catch { capabilities = capabilities with { Audio = false }; }
            return Results.Ok(new { pcName = Environment.MachineName, capabilities, audio, scheduler = scheduler.State, activity = scheduler.Activity.Recent, serverTime = DateTimeOffset.UtcNow });
        });
        app.MapPut("/api/v1/audio/volume", (VolumeRequest request) =>
        {
            return Results.Ok(new { accepted = true, feedback = commands.SetVolume(request.Volume) });
        });
        app.MapPut("/api/v1/audio/mute", (MuteRequest request) => Results.Ok(new { accepted = true, feedback = commands.SetMute(request.Muted) }));
        app.MapPost("/api/v1/audio/step", (VolumeStepRequest request) => Results.Ok(new { accepted = true, feedback = commands.StepVolume(request.Direction) }));
        app.MapPost("/api/v1/media", (MediaRequest request) =>
        {
            return Results.Ok(new { accepted = true, feedback = commands.Media(request.Action) });
        });
        app.MapPost("/api/v1/display/off", () => Results.Ok(new { accepted = true, feedback = commands.DisplaysOff() }));
        app.MapPost("/api/v1/power", (PowerRequest request) =>
        {
            if (!request.Confirmed) throw new ArgumentException("Power actions require explicit confirmation.");
            return Results.Accepted(value: scheduler.Schedule(request.Action, request.DelaySeconds));
        });
        app.MapDelete("/api/v1/power/{id:guid}", (Guid id) => scheduler.Cancel(id) ? Results.Ok(new { canceled = true }) : Results.NotFound(new { error = "Timer is no longer pending." }));
        try { await app.StartAsync(cancellationToken); return app; }
        catch { await app.DisposeAsync(); throw; }
    }
}
