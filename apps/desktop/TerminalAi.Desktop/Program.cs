namespace TerminalAi.Desktop;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        var root = ProjectRootResolver.Resolve(Environment.GetCommandLineArgs());
        using var app = new TerminalAiApplicationContext(root);
        Application.Run(app);
    }
}
