using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using Glance.Core.Logging;

namespace Glance.Platform;

/// <summary>
/// Ensures one Glance per user session. A second launch (Explorer "Open with", a
/// <c>glance://</c> deep link, a double-click while running) forwards its command-line
/// arguments to the running instance over a named pipe and exits.
/// Port of macOS <c>application(_:open:)</c> / Apple-event URL handling.
/// </summary>
public sealed class SingleInstance : IDisposable
{
    private readonly string _pipeName;
    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _cts = new();

    private SingleInstance(string name, Mutex mutex)
    {
        _pipeName = name;
        _mutex = mutex;
    }

    /// <summary>
    /// Raised on a thread-pool thread with the arguments a later launch forwarded.
    /// Handlers must marshal to the UI thread themselves.
    /// </summary>
    public event EventHandler<string[]>? ArgumentsReceived;

    /// <summary>
    /// Returns the primary-instance guard, or <c>null</c> after forwarding
    /// <paramref name="args"/> to the instance that is already running.
    /// </summary>
    public static SingleInstance? TryAcquire(string appId, string[] args)
    {
        var name = $"{appId}.{Environment.UserName}";
        var mutex = new Mutex(initiallyOwned: true, $@"Local\{name}", out var createdNew);
        if (createdNew) return new SingleInstance(name, mutex);

        mutex.Dispose();
        Forward(name, args);
        return null;
    }

    public void StartListening() => _ = Task.Run(() => ListenLoop(_cts.Token));

    private static void Forward(string pipeName, string[] args)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", pipeName, PipeDirection.Out, PipeOptions.CurrentUserOnly);
            client.Connect(TimeSpan.FromSeconds(2));
            var payload = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(args));
            client.Write(payload);
            client.Flush();
        }
        catch (Exception ex) when (ex is TimeoutException or IOException)
        {
            Log.Warning($"Could not forward arguments to the running instance: {ex.Message}");
        }
    }

    private async Task ListenLoop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try
            {
                await using var server = new NamedPipeServerStream(_pipeName, PipeDirection.In, 1,
                    PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(token);

                using var buffer = new MemoryStream();
                await server.CopyToAsync(buffer, token);
                var args = JsonSerializer.Deserialize<string[]>(buffer.ToArray()) ?? [];
                ArgumentsReceived?.Invoke(this, args);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception ex) when (ex is IOException or JsonException)
            {
                Log.Warning($"Single-instance pipe error: {ex.Message}");
            }
        }
    }

    public void Dispose()
    {
        _cts.Cancel();
        _cts.Dispose();
        _mutex.ReleaseMutex();
        _mutex.Dispose();
    }
}
