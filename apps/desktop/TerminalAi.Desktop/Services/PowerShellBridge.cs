namespace TerminalAi.Desktop;

internal sealed class PowerShellBridge
{
    private readonly string _root;
    private readonly ProcessLauncher _launcher;

    public PowerShellBridge(string root, ProcessLauncher launcher)
    {
        _root = root;
        _launcher = launcher;
    }

    public void OpenPanel(string text = "", string mode = "explain", IntPtr anchorHandle = default)
    {
        var inputFile = Path.GetTempFileName();
        File.WriteAllText(inputFile, text);
        _launcher.StartHidden("powershell.exe", new[]
        {
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", Script("apps", "powershell", "panel.ps1"),
            "-InputFile", inputFile,
            "-Mode", mode,
            "-PanelId", PanelId(anchorHandle),
            "-AnchorHandle", anchorHandle.ToInt64().ToString()
        });
    }

    public string? ShowCompletionPopup(string command)
    {
        var output = _launcher.RunCapture("powershell.exe", new[]
        {
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", Script("apps", "powershell", "complete-popup.ps1"),
            "-Prefix", command
        }, timeoutMs: 120000);

        return ParseCompletion(output);
    }

    public void OpenSshPanel()
    {
        _launcher.StartHidden("powershell.exe", new[]
        {
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", Script("apps", "powershell", "ssh-panel.ps1")
        });
    }

    public void OpenConfig()
    {
        OpenPanel(mode: "tools");
    }

    private string Script(params string[] parts)
    {
        return Path.Combine(new[] { _root }.Concat(parts).ToArray());
    }

    private static string PanelId(IntPtr anchorHandle)
    {
        return anchorHandle == IntPtr.Zero ? "desktop" : $"desktop-hwnd-{anchorHandle.ToInt64()}";
    }

    private static string? ParseCompletion(string output)
    {
        var text = output.Trim();
        if (string.IsNullOrWhiteSpace(text)) return null;
        try
        {
            using var json = System.Text.Json.JsonDocument.Parse(text);
            if (json.RootElement.TryGetProperty("completion", out var completion))
            {
                var value = completion.GetString();
                return string.IsNullOrWhiteSpace(value) ? null : value;
            }
        }
        catch
        {
            return text;
        }
        return null;
    }
}
