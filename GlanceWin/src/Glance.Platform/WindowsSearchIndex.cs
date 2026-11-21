using System.Data.OleDb;
using Glance.Core.Logging;
using Glance.Core.Search;

namespace Glance.Platform;

/// <summary>
/// Filename lookup in the Windows Search index (the Spotlight <c>mdfind</c> role on macOS).
/// Covers whatever the user has indexed (by default the user profile). Returns nothing — never
/// throws — when the Windows Search service is disabled.
/// </summary>
public sealed class WindowsSearchIndex : IIndexSearch
{
    private const string ConnectionString = "Provider=Search.CollatorDSO;Extended Properties='Application=Windows';";

    public IReadOnlyList<string> FindByFileName(string fileName, int limit, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(fileName)) return [];
        var escaped = fileName.Replace("'", "''");
        var sql = $"SELECT TOP {Math.Clamp(limit, 1, 200)} System.ItemPathDisplay FROM SystemIndex " +
                  $"WHERE SCOPE='file:' AND System.FileName = '{escaped}'";
        var results = new List<string>();
        try
        {
            using var connection = new OleDbConnection(ConnectionString);
            connection.Open();
            using var command = new OleDbCommand(sql, connection) { CommandTimeout = 2 };
            using var registration = cancellationToken.Register(() =>
            {
                try { command.Cancel(); } catch (Exception) { /* best effort */ }
            });
            using var reader = command.ExecuteReader();
            while (reader.Read() && !cancellationToken.IsCancellationRequested)
            {
                if (!reader.IsDBNull(0)) results.Add(reader.GetString(0));
            }
        }
        catch (Exception ex) when (ex is OleDbException or InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            Log.Info($"WindowsSearchIndex: unavailable ({ex.GetType().Name}: {ex.Message})");
        }
        return results;
    }
}
