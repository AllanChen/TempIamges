namespace Glance.Core.Content;

/// <summary>
/// File extension → language name (port of macOS <c>languageIdentifier(for:)</c>), plus the
/// matching AvalonEdit built-in highlighting where one exists.
/// </summary>
public static class CodeLanguage
{
    private static readonly Dictionary<string, string> Languages = new(StringComparer.OrdinalIgnoreCase)
    {
        ["swift"] = "swift", ["py"] = "python", ["js"] = "javascript", ["mjs"] = "javascript", ["cjs"] = "javascript",
        ["ts"] = "typescript", ["tsx"] = "tsx", ["jsx"] = "jsx", ["java"] = "java", ["kt"] = "kotlin",
        ["c"] = "c", ["h"] = "c", ["cpp"] = "cpp", ["cc"] = "cpp", ["cxx"] = "cpp", ["hpp"] = "cpp",
        ["rb"] = "ruby", ["go"] = "go", ["rs"] = "rust", ["php"] = "php", ["cs"] = "csharp", ["vb"] = "vb",
        ["lua"] = "lua", ["sh"] = "bash", ["bash"] = "bash", ["zsh"] = "zsh", ["fish"] = "fish",
        ["ps1"] = "powershell", ["psm1"] = "powershell", ["psd1"] = "powershell", ["bat"] = "batch", ["cmd"] = "batch",
        ["json"] = "json", ["jsonc"] = "json", ["xml"] = "xml", ["xaml"] = "xml", ["csproj"] = "xml", ["props"] = "xml",
        ["targets"] = "xml", ["resx"] = "xml", ["config"] = "xml", ["plist"] = "xml", ["svg"] = "xml", ["xshd"] = "xml",
        ["yaml"] = "yaml", ["yml"] = "yaml", ["ini"] = "ini", ["conf"] = "ini", ["cfg"] = "ini", ["toml"] = "toml",
        ["html"] = "html", ["htm"] = "html", ["css"] = "css", ["scss"] = "scss", ["sass"] = "scss", ["less"] = "less",
        ["sql"] = "sql", ["graphql"] = "graphql", ["gql"] = "graphql", ["proto"] = "protobuf", ["dart"] = "dart",
        ["scala"] = "scala", ["r"] = "r", ["pl"] = "perl", ["erl"] = "erlang", ["hs"] = "haskell", ["ml"] = "ocaml",
        ["fs"] = "fsharp", ["jl"] = "julia", ["tex"] = "latex", ["vue"] = "markup", ["svelte"] = "markup",
        ["astro"] = "astro", ["md"] = "markdown", ["markdown"] = "markdown", ["diff"] = "diff", ["patch"] = "diff",
    };

    /// <summary>Language for an extension (without the dot), or null for plain text.</summary>
    public static string? ForExtension(string extension) =>
        Languages.TryGetValue(extension.TrimStart('.'), out var language) ? language : null;

    /// <summary>
    /// Name of the AvalonEdit built-in highlighting definition for a language. Only close matches:
    /// a wrong grammar is worse than none.
    /// </summary>
    public static string? AvalonEditDefinition(string? language) => language switch
    {
        "csharp" => "C#",
        "javascript" or "typescript" or "tsx" or "jsx" => "JavaScript",
        "html" or "markup" or "astro" => "HTML",
        "xml" => "XML",
        "css" or "scss" or "less" => "CSS",
        "python" => "Python",
        "java" => "Java",
        "php" => "PHP",
        "c" or "cpp" => "C++",
        "powershell" => "PowerShell",
        "sql" => "TSQL",
        "vb" => "VB",
        "latex" => "TeX",
        "markdown" => "MarkDown",
        "json" => "Json",
        "diff" => "Patch",
        _ => null,
    };
}
