namespace TerminalAi.Desktop;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        var args = Environment.GetCommandLineArgs();
        var root = ProjectRootResolver.Resolve(args);
        var openCommandManager = args.Any(arg => string.Equals(arg, "--command-manager", StringComparison.OrdinalIgnoreCase));
        using var app = new TerminalAiApplicationContext(root, openCommandManager);
        Application.Run(app);
    }
}
