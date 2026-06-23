using System.Diagnostics;
using System.Text;

namespace TerminalAi.Desktop;

internal sealed class ProcessLauncher
{
    private readonly string _root;

    public ProcessLauncher(string root)
    {
        _root = root;
    }

    public Process StartHidden(string fileName, IEnumerable<string> args)
    {
        var info = new ProcessStartInfo
        {
            FileName = fileName,
            WorkingDirectory = _root,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        foreach (var arg in args) info.ArgumentList.Add(arg);
        return Process.Start(info) ?? throw new InvalidOperationException($"无法启动进程：{fileName}");
    }

    public string RunCapture(string fileName, IEnumerable<string> args, int timeoutMs = 15000)
    {
        var info = new ProcessStartInfo
        {
            FileName = fileName,
            WorkingDirectory = _root,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var arg in args) info.ArgumentList.Add(arg);

        using var process = Process.Start(info) ?? throw new InvalidOperationException($"无法启动进程：{fileName}");
        if (!process.WaitForExit(timeoutMs))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            throw new TimeoutException($"命令超时：{fileName}");
        }

        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderr) ? stdout : stderr);
        }
        return stdout;
    }
}
