using Glance.Core.Detection;
using Glance.Core.History;
using Glance.Core.Peek;
using Glance.Core.Search;
using Glance.Core.Settings;
using Xunit;

namespace Glance.Tests;

public sealed class SearchAndHistoryTests : IDisposable
{
    // Not under %TEMP%: the resolver deliberately skips AppData\Local\Temp.
    private readonly string _dir = Path.Combine(AppContext.BaseDirectory, "TestData", Guid.NewGuid().ToString("N"));

    public SearchAndHistoryTests() => Directory.CreateDirectory(_dir);

    [Theory]
    [InlineData("  \"screenshot.png\", ", "screenshot.png")]
    [InlineData("./assets/foo.png", @"assets\foo.png")]
    [InlineData(@"..\..\docs\readme.md.", @"docs\readme.md")]
    [InlineData("“报告.pdf”。", "报告.pdf")]
    public void NormalizeToken(string raw, string expected) =>
        Assert.Equal(expected, FileNameResolver.NormalizeToken(raw));

    [Theory]
    [InlineData(@"C:\Users\me\Desktop\img.png", "~\\Desktop")]
    [InlineData(@"C:\Users\me\img.png", "~")]
    [InlineData(@"C:\Users\me\Desktop\work\Project\assets\img.png", "…\\Project\\assets")]
    [InlineData(@"D:\x\img.png", @"D:\x")]
    public void DisambiguationHint(string path, string expected) =>
        Assert.Equal(expected, PeekPipeline.DisambiguationHint(path, @"C:\Users\me"));

    [Fact]
    public void FilenameCacheValidatesAndPersists()
    {
        var store = Path.Combine(_dir, "cache.json");
        var existing = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { @"C:\a\x.png" };
        var cache = new FilenameCache(store, existing.Contains);
        cache.Store("x.png", @"C:\a\x.png");
        cache.Store("gone.png", @"C:\a\gone.png");

        Assert.Equal(@"C:\a\x.png", cache.Lookup("X.PNG"));
        Assert.Null(cache.Lookup("gone.png"));
        Assert.Equal(1, cache.Count);
    }

    [Fact]
    public void FilenameCacheEvictsOldestBeyondLimit()
    {
        var cache = new FilenameCache(Path.Combine(_dir, "cache.json"), _ => true);
        for (var i = 0; i < 510; i++) cache.Store($"f{i}.png", $@"C:\f{i}.png");
        Assert.Equal(500, cache.Count);
    }

    [Fact]
    public async Task ResolverFindsFileByWalkingHome()
    {
        var home = Path.Combine(_dir, "home");
        var nested = Directory.CreateDirectory(Path.Combine(home, "Desktop", "work", "deep")).FullName;
        var target = Path.Combine(nested, "needle.png");
        await File.WriteAllBytesAsync(target, [1]);

        var env = new ResolverEnvironment(home, Path.Combine(home, "Desktop"), Path.Combine(home, "Documents"),
            Path.Combine(home, "Downloads"), []);
        var resolver = new FileNameResolver(env, new FilenameCache(Path.Combine(_dir, "c.json")), index: null);

        var matches = await resolver.ResolveAsync("needle.png");
        Assert.Equal(target, Assert.Single(matches).Path);

        var relative = await resolver.ResolveAsync(@"deep/needle.png");
        Assert.Equal(target, Assert.Single(relative).Path);
    }

    [Fact]
    public void HistoryKeepsResolvedItemsNewestFirstWithoutDuplicates()
    {
        var path = Path.Combine(_dir, "history.json");
        var history = new HistoryStore(path);
        var a = new DetectedPath(DetectedKind.LocalImage, @"C:\a.png");
        var b = new DetectedPath(DetectedKind.WebPage, "https://example.com/");
        history.Record([a, new DetectedPath(DetectedKind.UnresolvedFilename, "x.png")]);
        history.Record([b]);
        history.Record([a]);

        Assert.Equal(2, history.Records.Count);
        Assert.Equal(a.Value, history.Records[0].Items.Single().Value);
    }

    [Fact]
    public void HotkeyDisplayText()
    {
        Assert.Equal("Alt+Q", Hotkey.Default.DisplayText);
        Assert.Equal("Ctrl+Shift+F5", new Hotkey(HotkeyModifiers.Control | HotkeyModifiers.Shift, 0x74).DisplayText);
    }

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}
