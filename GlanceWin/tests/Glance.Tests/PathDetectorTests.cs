using Glance.Core.Detection;
using Xunit;

namespace Glance.Tests;

/// <summary>In-memory file system so detection tests don't depend on the machine.</summary>
internal sealed class FakeProbe : IFileProbe
{
    private readonly HashSet<string> _files = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _dirs = new(StringComparer.OrdinalIgnoreCase);

    public FakeProbe(params string[] paths)
    {
        foreach (var p in paths)
        {
            if (p.EndsWith('\\')) _dirs.Add(p.TrimEnd('\\'));
            else _files.Add(p);
        }
    }

    public string HomeDirectory => @"C:\Users\me";
    public bool FileExists(string path) => _files.Contains(path);
    public bool DirectoryExists(string path) => _dirs.Contains(path.TrimEnd('\\')) || (path.Length == 3 && path[1] == ':');
    public string ExpandEnvironmentVariables(string value) =>
        value.Replace("%USERPROFILE%", HomeDirectory, StringComparison.OrdinalIgnoreCase)
             .Replace("%APPDATA%", HomeDirectory + @"\AppData\Roaming", StringComparison.OrdinalIgnoreCase);
}

public sealed class PathDetectorTests
{
    private static IReadOnlyList<DetectedPath> Detect(string text, params string[] existing) =>
        new PathDetector(new FakeProbe(existing)).DetectAll(text);

    [Fact]
    public void LinkTextAndTargetCountOnce()
    {
        // macOS 7f399a7: "name.gif (folder/name.gif)" and "[name.gif](folder/name.gif)" resolve only the target.
        var target = System.IO.Path.Combine(@"C:" + System.IO.Path.DirectorySeparatorChar + "Users", "me", "assets", "demo.gif");
        Assert.Single(Detect("demo.gif (assets/demo.gif)", target));
        Assert.Single(Detect("[demo.gif](assets/demo.gif)", target));
        Assert.Equal(target, Detect("[demo.gif](assets/demo.gif)", target)[0].Value);
    }

    [Fact]
    public void DotInNameBeforeSpacedExtension()
    {
        // ".R" (R script) inside the name must not cut the path short; spaces before the real extension.
        const string file = @"D:\TempIamges\design\marketing\brand-assets\clipboard-DA224852-373C-472B-A405-9260B85880B6.Remove Objects.png";
        var quoted = Assert.Single(Detect($"PS D:\\> \"{file}\"", file));
        Assert.Equal(DetectedKind.LocalImage, quoted.Kind);
        Assert.Equal(file, quoted.Value);
        Assert.Equal(file, Assert.Single(Detect(file, file)).Value);
    }

    [Fact]
    public void RemoteImageUrl()
    {
        var hit = Assert.Single(Detect("look https://example.com/a/cat.png please"));
        Assert.Equal(DetectedKind.RemoteImage, hit.Kind);
        Assert.Equal("https://example.com/a/cat.png", hit.Value);
    }

    [Fact]
    public void UrlWithoutExtensionIsWebPage()
    {
        var hit = Assert.Single(Detect("see https://github.com/anthropics"));
        Assert.Equal(DetectedKind.WebPage, hit.Kind);
    }

    [Fact]
    public void RepairsMissingColonInScheme()
    {
        var hit = Assert.Single(Detect("https//example.com/x.jpg"));
        Assert.Equal(DetectedKind.RemoteImage, hit.Kind);
        Assert.StartsWith("https://", hit.Value);
    }

    [Fact]
    public void CdnQueryFormatAndBangSuffix()
    {
        Assert.Equal(DetectedKind.RemoteImage, Assert.Single(Detect("https://pbs.twimg.com/media/abc?format=jpg&name=large")).Kind);
        Assert.Equal(DetectedKind.RemoteImage, Assert.Single(Detect("https://sns-img.xhscdn.com/abc!nc_n_webp_mw_1")).Kind);
    }

    [Fact]
    public void BareDomainBecomesHttps()
    {
        var hit = Assert.Single(Detect("go to github.com/user/repo/readme.md now"));
        Assert.Equal(DetectedKind.RemoteMarkdown, hit.Kind);
        Assert.Equal("https://github.com/user/repo/readme.md", hit.Value);
    }

    [Fact]
    public void WindowsDrivePathWithSpacesAndParentheses()
    {
        const string path = @"C:\Users\me\Pictures\Trip 2024\photo (1).png";
        var hit = Assert.Single(Detect($"saved to {path}.", path));
        Assert.Equal(DetectedKind.LocalImage, hit.Kind);
        Assert.Equal(path, hit.Value);
    }

    [Fact]
    public void ForwardSlashDrivePathIsNormalized()
    {
        var hit = Assert.Single(Detect("C:/Users/me/notes.md", @"C:\Users\me\notes.md"));
        Assert.Equal(DetectedKind.LocalMarkdown, hit.Kind);
        Assert.Equal(@"C:\Users\me\notes.md", hit.Value);
    }

    [Fact]
    public void HomeAndEnvironmentPaths()
    {
        Assert.Equal(@"C:\Users\me\Desktop\a.pdf",
            Assert.Single(Detect(@"~\Desktop\a.pdf", @"C:\Users\me\Desktop\a.pdf")).Value);
        Assert.Equal(@"C:\Users\me\AppData\Roaming\x\log.txt",
            Assert.Single(Detect(@"%APPDATA%\x\log.txt", @"C:\Users\me\AppData\Roaming\x\log.txt")).Value);
    }

    [Fact]
    public void WslAndGitBashPathsMapToDrives()
    {
        Assert.Equal(@"D:\work\clip.mp4", Assert.Single(Detect("/mnt/d/work/clip.mp4", @"D:\work\clip.mp4")).Value);
        Assert.Equal(@"D:\work\clip.mp4", Assert.Single(Detect("/d/work/clip.mp4", @"D:\work\clip.mp4")).Value);
    }

    [Fact]
    public void FileUrl()
    {
        var hit = Assert.Single(Detect("file:///C:/Users/me/a%20b.png", @"C:\Users\me\a b.png"));
        Assert.Equal(DetectedKind.LocalImage, hit.Kind);
        Assert.Equal(@"C:\Users\me\a b.png", hit.Value);
    }

    [Fact]
    public void MissingAbsoluteFileIsNotAHit()
    {
        Assert.DoesNotContain(Detect(@"C:\nope\gone.png"), h => h.Kind == DetectedKind.LocalImage);
    }

    [Fact]
    public void LazyMatchExtendsPastDotFolders()
    {
        const string path = @"C:\Users\me\.config\settings.json";
        Assert.Equal(path, Assert.Single(Detect(path, path)).Value);
    }

    [Fact]
    public void RelativePathUnderHomeResolvesDirectly()
    {
        var hit = Assert.Single(Detect(@"Desktop\work\Guide.pdf", @"C:\Users\me\Desktop\work\Guide.pdf"));
        Assert.Equal(DetectedKind.LocalPdf, hit.Kind);
    }

    [Fact]
    public void UnknownRelativePathIsUnresolved()
    {
        var hit = Assert.Single(Detect("assets/img/logo.svg"));
        Assert.Equal(DetectedKind.UnresolvedRelativePath, hit.Kind);
        Assert.Equal("assets/img/logo.svg", hit.Value);
    }

    [Fact]
    public void DottedFolderNameIsRelativePathNotDomain()
    {
        var hit = Assert.Single(Detect("Glance.App/App.xaml"));
        Assert.Equal(DetectedKind.UnresolvedRelativePath, hit.Kind);
    }

    [Fact]
    public void BareFilenameAlsoTriesLastWord()
    {
        var hits = Detect("please open my photo.png");
        Assert.Contains(hits, h => h is { Kind: DetectedKind.UnresolvedFilename, Value: "photo.png" });
    }

    [Fact]
    public void BareNameInsideResolvedPathIsNotDuplicated()
    {
        const string path = @"C:\Users\me\My Docs\a b.png";
        var hits = Detect(path, path);
        Assert.Single(hits);
    }

    [Fact]
    public void CommaSeparatedListSplits()
    {
        var hits = Detect(@"C:\a\x.png,C:\a\y.png", @"C:\a\x.png", @"C:\a\y.png");
        Assert.Equal(2, hits.Count);
    }

    [Fact]
    public void FolderFallbackTrimsTrailingWords()
    {
        var hit = Assert.Single(Detect(@"open C:\Users\me\Project Files now", @"C:\Users\me\Project Files\"));
        Assert.Equal(DetectedKind.LocalFolder, hit.Kind);
        Assert.Equal(@"C:\Users\me\Project Files", hit.Value);
    }

    [Fact]
    public void TypeScriptIsTextNotVideo()
    {
        Assert.Equal(DetectedKind.LocalText, Assert.Single(Detect(@"C:\src\app.ts", @"C:\src\app.ts")).Kind);
    }

    [Fact]
    public void EmptyAndPlainProse()
    {
        Assert.Empty(Detect("   "));
        // Like macOS, plain words become at most three extension-less search tokens.
        var prose = Detect("hello there, how are you");
        Assert.InRange(prose.Count, 1, 3);
        Assert.All(prose, h => Assert.Equal(DetectedKind.UnresolvedFilename, h.Kind));
    }

    [Theory]
    [InlineData(@"C:\a\photo.PNG", "png")]
    [InlineData("https://x.com/a/b.tar.gz", "gz")]
    [InlineData(@"C:\a\.gitignore", "")]
    [InlineData(@"C:\a\folder\", "")]
    [InlineData("noext", "")]
    public void ExtensionOf(string path, string expected) => Assert.Equal(expected, FileKinds.ExtensionOf(path));
}
