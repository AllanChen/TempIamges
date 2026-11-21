using Glance.Core.Localization;
using Glance.Core.Settings;
using Xunit;

namespace Glance.Tests;

public class LocalizationTests
{
    [Fact]
    public void ParsesAppleStringsFiles()
    {
        const string text = """
            /* Header
               comment */
            // MARK: - App
            "Glance" = "Glance";
            "Open Files…" = "打开文件…";
            "Quote \"x\"" = "引号 \"x\"";
            "Version %@\n\nAbout" = "版本 %@\n\n关于";
            "Broken" "missing equals";
            "Spaced"   =   "值" ;
            """;
        var table = StringsFile.Parse(text);
        Assert.Equal("Glance", table["Glance"]);
        Assert.Equal("打开文件…", table["Open Files…"]);
        Assert.Equal("引号 \"x\"", table["Quote \"x\""]);
        Assert.Equal("版本 %@\n\n关于", table["Version %@\n\nAbout"]);
        Assert.Equal("值", table["Spaced"]);
        Assert.False(table.ContainsKey("Broken"));
    }

    [Fact]
    public void FormatsMacSpecifiers()
    {
        Assert.Equal("3 of 5", StringsFile.Format("%1$d of %2$d", 3, 5));
        Assert.Equal("5 / 3", StringsFile.Format("%2$d / %1$d", 3, 5));
        Assert.Equal("a 1 b", StringsFile.Format("%@ %ld %@", "a", 1, "b"));
        Assert.Equal("100%", StringsFile.Format("%d%%", 100));
        Assert.Equal("x ", StringsFile.Format("%@ %@", "x"));
    }

    [Fact]
    public void RealChineseFileLoads()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "..", "clients", "macos", "Glance", "Resources", "zh-Hans.lproj", "Localizable.strings");
        if (!File.Exists(path)) return;
        var table = StringsFile.Parse(File.ReadAllText(path));
        Assert.True(table.Count > 800);
        Assert.Equal("帮助", table["Help"]);
    }

    /// <summary>
    /// Every literal key the app passes to <c>L.T</c> / <c>L.F</c> (including both branches of a
    /// ternary) has Chinese in the macOS table or the Windows supplement; otherwise that text stays
    /// English when the user picks Chinese.
    /// </summary>
    [Fact]
    public void EveryUiStringHasChinese()
    {
        var root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
        var app = Path.Combine(root, "src", "Glance.App");
        var macos = Path.Combine(root, "..", "clients", "macos", "Glance", "Resources", "zh-Hans.lproj", "Localizable.strings");
        var windows = Path.Combine(app, "Localization", "zh-Hans.windows.strings");
        if (!Directory.Exists(app) || !File.Exists(macos)) return;
        Assert.True(File.Exists(windows));
        var keys = new HashSet<string>(StringFile(macos).Keys.Concat(StringFile(windows).Keys), StringComparer.Ordinal);

        const string lit = "\"((?:[^\"\\\\]|\\\\.)*)\"";
        var direct = new System.Text.RegularExpressions.Regex(@"L\.[TF]\(\s*" + lit);
        var ternary = new System.Text.RegularExpressions.Regex(@"L\.[TF]\(\s*[^""(),;\n]*\?\s*" + lit + @"\s*:\s*" + lit + @"\s*[,)]");
        var missing = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var file in Directory.EnumerateFiles(app, "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") || file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")) continue;
            var source = File.ReadAllText(file);
            var found = direct.Matches(source).Select(m => m.Groups[1].Value)
                .Concat(ternary.Matches(source).SelectMany(m => new[] { m.Groups[1].Value, m.Groups[2].Value }));
            foreach (var raw in found)
            {
                var key = raw.Replace("\\\"", "\"").Replace("\\n", "\n");
                if (!keys.Contains(key)) missing.Add($"{Path.GetFileName(file)}: {key}");
            }
        }
        Assert.True(missing.Count == 0, "No Chinese for:\n" + string.Join("\n", missing));
    }

    [Fact]
    public void WindowsSupplementParses()
    {
        var path = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "src", "Glance.App", "Localization", "zh-Hans.windows.strings"));
        if (!File.Exists(path)) return;
        var table = StringFile(path);
        Assert.Equal("打开一张图片开始。", table["Open an image to begin."]);
        Assert.Equal("3 张图片已就绪。", StringsFile.Format(table["%d images ready."], 3));
        Assert.Equal("任务失败 · 停在 40%", StringsFile.Format(table["Task failed · Stopped at %d%%"], 40));
    }

    private static IReadOnlyDictionary<string, string> StringFile(string path) => StringsFile.Parse(File.ReadAllText(path));

    [Theory]
    [InlineData("zh-CN", AppLanguage.Chinese)]
    [InlineData("zh-Hans-SG", AppLanguage.Chinese)]
    [InlineData("zh", AppLanguage.Chinese)]
    [InlineData("zh-TW", AppLanguage.English)]
    [InlineData("zh-Hant-HK", AppLanguage.English)]
    [InlineData("en-US", AppLanguage.English)]
    [InlineData("ja-JP", AppLanguage.English)]
    public void SystemLanguageDetection(string culture, AppLanguage expected) => Assert.Equal(expected, AppSettings.LanguageFor(culture));
}
