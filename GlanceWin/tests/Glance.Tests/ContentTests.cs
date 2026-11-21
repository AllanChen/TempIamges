using System.Text;
using Glance.Core.Content;
using Glance.Core.Git;
using Xunit;

namespace Glance.Tests;

public sealed class TextFileCodecTests : IDisposable
{
    private readonly string _dir = Path.Combine(AppContext.BaseDirectory, "TestData", Guid.NewGuid().ToString("N"));

    public TextFileCodecTests() => Directory.CreateDirectory(_dir);

    [Fact]
    public void Utf8WithoutBom()
    {
        var decoded = TextFileCodec.Decode(Encoding.UTF8.GetBytes("héllo 你好"));
        Assert.Equal("héllo 你好", decoded.Text);
        Assert.Equal(65001, decoded.Encoding.CodePage);
        Assert.False(decoded.HasBom);
    }

    [Fact]
    public void Utf8BomIsStrippedAndKept()
    {
        var bytes = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(Encoding.UTF8.GetBytes("a\r\nb")).ToArray();
        var decoded = TextFileCodec.Decode(bytes);
        Assert.Equal("a\r\nb", decoded.Text);
        Assert.True(decoded.HasBom);
        Assert.Equal(bytes, TextFileCodec.Encode(decoded.Text, decoded.Encoding));
    }

    [Fact]
    public void Utf16LittleEndianBom()
    {
        var bytes = Encoding.Unicode.GetPreamble().Concat(Encoding.Unicode.GetBytes("x=1")).ToArray();
        var decoded = TextFileCodec.Decode(bytes);
        Assert.Equal("x=1", decoded.Text);
        Assert.Equal(bytes, TextFileCodec.Encode(decoded.Text, decoded.Encoding));
    }

    [Fact]
    public void InvalidUtf8FallsBackToLegacyCodePage()
    {
        _ = TextFileCodec.Utf8; // registers code pages
        var gbk = Encoding.GetEncoding(936);
        var bytes = gbk.GetBytes("中文注释");
        var decoded = TextFileCodec.Decode(bytes, gbk);
        Assert.Equal("中文注释", decoded.Text);
        Assert.Equal(936, decoded.Encoding.CodePage);
        Assert.Equal(bytes, TextFileCodec.Encode(decoded.Text, decoded.Encoding));
    }

    [Fact]
    public void LegacyCodePageRejectsUnrepresentableCharacters()
    {
        _ = TextFileCodec.Utf8;
        var gbk = Encoding.GetEncoding(936);
        Assert.Throws<EncoderFallbackException>(() => TextFileCodec.Encode("emoji 😀", gbk));
    }

    [Fact]
    public void WriteAtomicReplacesContentAndLeavesNoTempFile()
    {
        var path = Path.Combine(_dir, "note.txt");
        File.WriteAllText(path, "old");
        TextFileCodec.WriteAtomic(path, Encoding.UTF8.GetBytes("new"));
        Assert.Equal("new", File.ReadAllText(path));
        Assert.Single(Directory.GetFiles(_dir));
    }

    [Fact]
    public void WriteAtomicCreatesMissingFile()
    {
        var path = Path.Combine(_dir, "fresh.md");
        TextFileCodec.WriteAtomic(path, Encoding.UTF8.GetBytes("# hi"));
        Assert.Equal("# hi", File.ReadAllText(path));
        Assert.Single(Directory.GetFiles(_dir));
    }

    [Theory]
    [InlineData("cs", "C#")]
    [InlineData("tsx", "JavaScript")]
    [InlineData("csproj", "XML")]
    [InlineData("PS1", "PowerShell")]
    [InlineData("rs", null)]
    [InlineData("log", null)]
    public void HighlightingForExtension(string extension, string? expected) =>
        Assert.Equal(expected, CodeLanguage.AvalonEditDefinition(CodeLanguage.ForExtension(extension)));

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch (IOException) { }
    }
}

public sealed class LineDiffTests
{
    [Fact]
    public void IdenticalTextIsAllUnchanged()
    {
        var rows = LineDiff.Rows("a\nb\nc\n", "a\nb\nc");
        Assert.Equal(3, rows.Count);
        Assert.All(rows, r => Assert.Equal(DiffKind.Unchanged, r.Left.Kind));
        Assert.Equal(3, rows[2].Right.Number);
    }

    [Fact]
    public void ChangedLineIsPairedDeleteInsert()
    {
        var rows = LineDiff.Rows("a\nb\nc", "a\nB\nc");
        Assert.Equal(3, rows.Count);
        Assert.Equal(new DiffCell(2, "b", DiffKind.Deleted), rows[1].Left);
        Assert.Equal(new DiffCell(2, "B", DiffKind.Inserted), rows[1].Right);
        Assert.Equal(new DiffCell(3, "c", DiffKind.Unchanged), rows[2].Left);
    }

    [Fact]
    public void InsertionPadsTheLeftSide()
    {
        var rows = LineDiff.Rows("a\nc", "a\nb1\nb2\nc");
        Assert.Equal(4, rows.Count);
        Assert.Equal(DiffKind.Placeholder, rows[1].Left.Kind);
        Assert.Null(rows[1].Left.Number);
        Assert.Equal(new DiffCell(3, "b2", DiffKind.Inserted), rows[2].Right);
        Assert.Equal(new DiffCell(2, "c", DiffKind.Unchanged), rows[3].Left);
        Assert.Equal(new DiffCell(4, "c", DiffKind.Unchanged), rows[3].Right);
    }

    [Fact]
    public void NewFileIsAllInserted()
    {
        var rows = LineDiff.Rows("", "x\ny");
        Assert.Equal(2, rows.Count);
        Assert.All(rows, r => Assert.Equal(DiffKind.Placeholder, r.Left.Kind));
        Assert.All(rows, r => Assert.Equal(DiffKind.Inserted, r.Right.Kind));
    }

    [Fact]
    public void EmptyBothSidesYieldsOnePlaceholderRow()
    {
        var rows = LineDiff.Rows("", "");
        Assert.Single(rows);
        Assert.Equal(DiffKind.Placeholder, rows[0].Left.Kind);
    }

    [Fact]
    public void CrLfAndLfCompareEqual()
    {
        var rows = LineDiff.Rows("a\r\nb\r\n", "a\nb\n");
        Assert.All(rows, r => Assert.Equal(DiffKind.Unchanged, r.Right.Kind));
    }

    [Fact]
    public void LargeRewriteUsesPositionalFallback()
    {
        var before = string.Join('\n', Enumerable.Range(0, 3000).Select(i => $"old {i}"));
        var after = string.Join('\n', Enumerable.Range(0, 3000).Select(i => $"new {i}"));
        var rows = LineDiff.Rows(before, after);
        Assert.Equal(3000, rows.Count);
        Assert.Equal(new DiffCell(3000, "old 2999", DiffKind.Deleted), rows[^1].Left);
    }
}

public sealed class GitDiffServiceTests : IDisposable
{
    private readonly string _root = Path.Combine(AppContext.BaseDirectory, "TestData", Guid.NewGuid().ToString("N"));
    private readonly string _file;

    public GitDiffServiceTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "src"));
        _file = Path.Combine(_root, "src", "app.cs");
        File.WriteAllText(_file, "after\n");
    }

    [Theory]
    [InlineData(@"C:\repo", @"C:\repo\src\a.cs", "src/a.cs")]
    [InlineData(@"C:\repo", @"c:\REPO\a.cs", "a.cs")]
    [InlineData(@"C:\repo", @"C:\other\a.cs", null)]
    [InlineData(@"C:\repo", @"C:\repo", null)]
    public void RelativePath(string root, string file, string? expected) =>
        Assert.Equal(expected, GitDiffService.RelativePath(root, file));

    [Fact]
    public async Task ModifiedFileComparesHeadWithWorkingTree()
    {
        var git = new FakeGit(_root)
        {
            Status = " M src/app.cs",
            History = "abcdef1234567\n1234567abcdef\n",
            Tracked = true,
            Files = { ["HEAD:src/app.cs"] = "before\n" },
        };
        var service = new GitDiffService(git);

        var context = await service.ContextAsync(_file);
        Assert.NotNull(context);
        Assert.Equal("src/app.cs", context.RelativePath);
        Assert.Equal(Path.GetFullPath(_root), context.Root);

        var snapshot = await service.SnapshotAsync(context);
        Assert.Equal("Before - HEAD", snapshot.BeforeTitle);
        Assert.Equal("After - Working Tree", snapshot.AfterTitle);
        Assert.Equal("before\n", snapshot.BeforeText);
        Assert.Equal("after\n", snapshot.AfterText);
    }

    [Fact]
    public async Task CleanFileShowsLastCommittedChange()
    {
        var git = new FakeGit(_root)
        {
            History = "aaaaaaa1111\nbbbbbbb2222\n",
            Tracked = true,
            Files = { ["aaaaaaa1111:src/app.cs"] = "v2", ["bbbbbbb2222:src/app.cs"] = "v1" },
        };
        var service = new GitDiffService(git);
        var snapshot = await service.SnapshotAsync((await service.ContextAsync(_file))!);
        Assert.Equal("Before - bbbbbbb", snapshot.BeforeTitle);
        Assert.Equal("After - aaaaaaa", snapshot.AfterTitle);
        Assert.Equal("v1", snapshot.BeforeText);
        Assert.Equal("v2", snapshot.AfterText);
    }

    [Fact]
    public async Task OutsideRepositoryHasNoContext()
    {
        var git = new FakeGit(null);
        Assert.Null(await new GitDiffService(git).ContextAsync(_file));
    }

    [Fact]
    public async Task UntrackedCleanFileHasNoContext()
    {
        var git = new FakeGit(_root);
        Assert.Null(await new GitDiffService(git).ContextAsync(_file));
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch (IOException) { }
    }

    private sealed class FakeGit(string? root) : IGitRunner
    {
        public string Status { get; init; } = "";
        public string History { get; init; } = "";
        public bool Tracked { get; init; }
        public Dictionary<string, string> Files { get; } = [];

        public Task<GitResult?> RunAsync(IReadOnlyList<string> arguments, string workingDirectory, CancellationToken ct = default)
        {
            GitResult Ok(string text) => new(0, Encoding.UTF8.GetBytes(text));
            GitResult Fail() => new(128, []);
            var result = arguments[0] switch
            {
                "rev-parse" => root is null ? Fail() : Ok(root.Replace('\\', '/') + "\n"),
                "--no-optional-locks" => Ok(Status),
                "log" => Ok(History),
                "ls-files" => Tracked ? Ok("src/app.cs\n") : Fail(),
                "show" => Files.TryGetValue(arguments[^1], out var text) ? Ok(text) : Fail(),
                _ => Fail(),
            };
            return Task.FromResult<GitResult?>(result);
        }
    }
}
