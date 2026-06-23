using System.Diagnostics;

namespace TerminalAi.Desktop;

internal sealed class LocalServerManager : IDisposable
{
    private readonly string _root;
    private readonly ProcessLauncher _launcher;
    private Process? _process;

    public LocalServerManager(string root, ProcessLauncher launcher)
    {
        _root = root;
        _launcher = launcher;
    }

    public bool IsRunning => _process is { HasExited: false };

    public void Start(int port = 17888, bool replace = false)
    {
        if (IsRunning) return;
        var args = new List<string>
        {
            Path.Combine(_root, "bin", "taih.js"),
            "serve",
            "--port",
            port.ToString()
        };
        if (replace) args.Add("--replace");
        _process = _launcher.StartHidden("node.exe", args);
    }

    public void Stop()
    {
        if (_process is null) return;
        try
        {
            if (!_process.HasExited) _process.Kill(entireProcessTree: true);
        }
        catch { }
        try { _process.Dispose(); } catch { }
        _process = null;
    }

    public void Dispose() => Stop();
}
