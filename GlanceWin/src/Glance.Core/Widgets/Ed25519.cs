using System.Numerics;
using System.Security.Cryptography;

namespace Glance.Core.Widgets;

/// <summary>
/// Ed25519 signature verification (RFC 8032 §5.1.7), verify-only. Replaces BouncyCastle, which
/// added 11 MB to the package for this one check. Only public data is handled (manifest, public
/// key, signature), so the simple variable-time <see cref="BigInteger"/> arithmetic is fine.
/// Same rules as BouncyCastle: S must be below L, the public key must decode to a curve point
/// with y below p, and the encoding of [S]B − [k]A must equal R byte for byte.
/// </summary>
public static class Ed25519
{
    private static readonly BigInteger P = BigInteger.Pow(2, 255) - 19;
    private static readonly BigInteger L = BigInteger.Pow(2, 252) + BigInteger.Parse("27742317777372353535851937790883648493");
    private static readonly BigInteger D = Mod(-121665 * Inverse(121666));
    private static readonly BigInteger D2 = Mod(2 * D);
    private static readonly BigInteger SqrtM1 = BigInteger.ModPow(2, (P - 1) / 4, P);
    private static readonly Point Base = Decode(Encode(Mod(4 * Inverse(5)), signBit: false)) ?? throw new InvalidOperationException("Ed25519 base point");
    private static readonly Point Identity = new(0, 1, 1, 0);

    public static bool Verify(ReadOnlySpan<byte> publicKey, ReadOnlySpan<byte> message, ReadOnlySpan<byte> signature)
    {
        if (publicKey.Length != 32 || signature.Length != 64) return false;
        var s = Scalar(signature[32..]);
        if (s >= L) return false;
        if (Decode(publicKey) is not { } a) return false;

        var hashInput = new byte[64 + message.Length];
        signature[..32].CopyTo(hashInput);
        publicKey.CopyTo(hashInput.AsSpan(32));
        message.CopyTo(hashInput.AsSpan(64));
        var k = Scalar(SHA512.HashData(hashInput)) % L;

        var check = Add(Multiply(Base, s), Multiply(Negate(a), k));
        return EncodePoint(check).AsSpan().SequenceEqual(signature[..32]);
    }

    private readonly record struct Point(BigInteger X, BigInteger Y, BigInteger Z, BigInteger T);

    private static BigInteger Mod(BigInteger v)
    {
        var r = v % P;
        return r.Sign < 0 ? r + P : r;
    }

    private static BigInteger Inverse(BigInteger v) => BigInteger.ModPow(Mod(v), P - 2, P);

    private static BigInteger Scalar(ReadOnlySpan<byte> littleEndian) => new(littleEndian, isUnsigned: true, isBigEndian: false);

    /// <summary>Extended twisted-Edwards addition (a = −1), RFC 8032 §5.1.4; also used for doubling.</summary>
    private static Point Add(Point p, Point q)
    {
        var a = Mod((p.Y - p.X) * (q.Y - q.X));
        var b = Mod((p.Y + p.X) * (q.Y + q.X));
        var c = Mod(p.T * D2 * q.T);
        var d = Mod(2 * p.Z * q.Z);
        BigInteger e = b - a, f = d - c, g = d + c, h = b + a;
        return new Point(Mod(e * f), Mod(g * h), Mod(f * g), Mod(e * h));
    }

    private static Point Negate(Point p) => new(Mod(-p.X), p.Y, p.Z, Mod(-p.T));

    private static Point Multiply(Point p, BigInteger scalar)
    {
        var result = Identity;
        var addend = p;
        while (scalar.Sign > 0)
        {
            if (!scalar.IsEven) result = Add(result, addend);
            addend = Add(addend, addend);
            scalar >>= 1;
        }
        return result;
    }

    private static byte[] Encode(BigInteger y, bool signBit)
    {
        var bytes = new byte[32];
        y.TryWriteBytes(bytes, out _, isUnsigned: true, isBigEndian: false);
        if (signBit) bytes[31] |= 0x80;
        return bytes;
    }

    private static byte[] EncodePoint(Point p)
    {
        var zInv = Inverse(p.Z);
        return Encode(Mod(p.Y * zInv), !Mod(p.X * zInv).IsEven);
    }

    /// <summary>Point decompression, RFC 8032 §5.1.3. Null when the bytes aren't a canonical curve point.</summary>
    private static Point? Decode(ReadOnlySpan<byte> encoded)
    {
        Span<byte> bytes = stackalloc byte[32];
        encoded.CopyTo(bytes);
        var sign = (bytes[31] & 0x80) != 0;
        bytes[31] &= 0x7f;
        var y = Scalar(bytes);
        if (y >= P) return null;

        var y2 = Mod(y * y);
        var x2 = Mod((y2 - 1) * Inverse(D * y2 + 1));
        var x = BigInteger.ModPow(x2, (P + 3) / 8, P);
        if (Mod(x * x - x2) != 0) x = Mod(x * SqrtM1);
        if (Mod(x * x - x2) != 0) return null;
        if (x.IsZero && sign) return null;
        if (!x.IsEven != sign) x = P - x;
        return new Point(x, y, 1, Mod(x * y));
    }
}
