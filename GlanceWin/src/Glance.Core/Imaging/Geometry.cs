namespace Glance.Core.Imaging;

/// <summary>Point in DIPs or pixels, top-left origin (WPF / Figma orientation).</summary>
public readonly record struct PointD(double X, double Y);

/// <summary>Size in DIPs or pixels.</summary>
public readonly record struct SizeD(double Width, double Height)
{
    public bool IsEmpty => Width <= 0 || Height <= 0;
}

/// <summary>Rectangle with a top-left origin. Platform-neutral so the maths stays unit-testable.</summary>
public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double Left => X;
    public double Top => Y;
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public double MidX => X + Width / 2;
    public double MidY => Y + Height / 2;
    public bool IsEmpty => Width <= 0 || Height <= 0;

    public bool Contains(PointD p) => p.X >= X && p.X <= Right && p.Y >= Y && p.Y <= Bottom;

    public RectD Intersect(RectD other)
    {
        var left = Math.Max(X, other.X);
        var top = Math.Max(Y, other.Y);
        var right = Math.Min(Right, other.Right);
        var bottom = Math.Min(Bottom, other.Bottom);
        return right <= left || bottom <= top ? default : new RectD(left, top, right - left, bottom - top);
    }

    public RectD Union(RectD other)
    {
        if (IsEmpty) return other;
        if (other.IsEmpty) return this;
        var left = Math.Min(X, other.X);
        var top = Math.Min(Y, other.Y);
        return new RectD(left, top, Math.Max(Right, other.Right) - left, Math.Max(Bottom, other.Bottom) - top);
    }

    public RectD Inflate(double dx, double dy) => new(X - dx, Y - dy, Width + dx * 2, Height + dy * 2);

    public RectD Offset(double dx, double dy) => new(X + dx, Y + dy, Width, Height);
}
