namespace TerminalAi.Desktop;

internal static class ProjectRootResolver
{
    public static string Resolve(string[] args)
    {
        var cliRoot = ReadOption(args, "--root");
        if (LooksLikeRoot(cliRoot)) return Path.GetFullPath(cliRoot!);

        var envRoot = Environment.GetEnvironmentVariable("TAIH_ROOT");
        if (LooksLikeRoot(envRoot)) return Path.GetFullPath(envRoot!);

        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (LooksLikeRoot(current.FullName)) return current.FullName;
            current = current.Parent;
        }

        throw new InvalidOperationException("找不到 terminal-ai-helper 项目根目录。请使用 --root <项目目录> 或设置 TAIH_ROOT。");
    }

    private static string? ReadOption(string[] args, string name)
    {
        for (var index = 0; index < args.Length - 1; index++)
        {
            if (string.Equals(args[index], name, StringComparison.OrdinalIgnoreCase))
            {
                return args[index + 1];
            }
        }
        return null;
    }

    private static bool LooksLikeRoot(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        try
        {
            var root = Path.GetFullPath(path);
            return File.Exists(Path.Combine(root, "bin", "taih.js"))
                && File.Exists(Path.Combine(root, "package.json"))
                && Directory.Exists(Path.Combine(root, "src"));
        }
        catch
        {
            return false;
        }
    }
}
