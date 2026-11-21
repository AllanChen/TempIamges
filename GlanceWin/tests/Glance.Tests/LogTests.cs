using Glance.Core.Logging;
using Xunit;

namespace Glance.Tests;

public sealed class LogTests
{
    [Fact]
    public void FormatMatchesMacOSLogLayout()
    {
        var line = Log.Format(new DateTime(2026, 11, 19, 9, 5, 3, 42), LogLevel.Warning, "hello",
            @"D:\src\Glance.Core\Thing.cs", "DoWork", 12);

        Assert.Equal("[2026-11-19 09:05:03.042] [WARN] [Thing.cs:12] DoWork - hello", line);
    }

    [Fact]
    public void RedactHidesContentOutsideDebug()
    {
        var redacted = Log.Redact(@"C:\Users\me\secret.png");
#if DEBUG
        Assert.Equal(@"C:\Users\me\secret.png", redacted);
#else
        Assert.Equal("<redacted 22 chars>", redacted);
#endif
    }
}
