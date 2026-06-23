using System.Text.RegularExpressions;
using System.Windows.Automation;

namespace TerminalAi.Desktop;

internal sealed record TerminalContext(IntPtr Handle, string Text, string Command, string Error);

internal sealed class TerminalCaptureService
{
    private const int MaxTextLength = 40000;

    public TerminalContext GetForegroundContext()
    {
        var handle = NativeMethods.GetForegroundWindow();
        var text = "";
        var command = "";
        var error = "";
        try
        {
            text = GetVisibleText(handle);
            command = ExtractCommand(text);
        }
        catch (Exception ex)
        {
            error = ex.Message;
        }
        return new TerminalContext(handle, text, command, error);
    }

    public void ReplaceCurrentCommand(IntPtr handle, string existingText, string newText)
    {
        if (handle == IntPtr.Zero || !NativeMethods.IsWindow(handle))
        {
            throw new InvalidOperationException("目标终端窗口不可用。");
        }

        var oldClipboard = "";
        try { oldClipboard = Clipboard.GetText(); } catch { }
        NativeMethods.SetForegroundWindow(handle);
        Thread.Sleep(120);
        SendKeys.SendWait("{END}");
        Thread.Sleep(50);
        SendBackspace(string.IsNullOrEmpty(existingText) ? 240 : existingText.Length);
        Thread.Sleep(50);
        Clipboard.SetText(newText);
        Thread.Sleep(80);
        SendKeys.SendWait("^v");
        Thread.Sleep(120);
        if (!string.IsNullOrEmpty(oldClipboard))
        {
            try { Clipboard.SetText(oldClipboard); } catch { }
        }
    }

    private static void SendBackspace(int count)
    {
        var remaining = Math.Max(0, count);
        while (remaining > 0)
        {
            var chunk = Math.Min(remaining, 60);
            SendKeys.SendWait($"{{BACKSPACE {chunk}}}");
            Thread.Sleep(20);
            remaining -= chunk;
        }
    }

    private static string GetVisibleText(IntPtr handle)
    {
        if (handle == IntPtr.Zero) return "";
        var root = AutomationElement.FromHandle(handle);
        if (root is null) return "";

        var candidates = new List<string>();
        AddElementText(candidates, root);
        var all = root.FindAll(TreeScope.Descendants, Condition.TrueCondition);
        foreach (AutomationElement element in all)
        {
            AddElementText(candidates, element);
        }

        return candidates
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .OrderByDescending(value => value.Length)
            .FirstOrDefault() ?? "";
    }

    private static void AddElementText(List<string> values, AutomationElement element)
    {
        try
        {
            if (element.TryGetCurrentPattern(TextPattern.Pattern, out var textPatternObj)
                && textPatternObj is TextPattern textPattern)
            {
                var text = textPattern.DocumentRange.GetText(MaxTextLength);
                if (!string.IsNullOrWhiteSpace(text)) values.Add(text);
            }
        }
        catch { }

        try
        {
            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var valuePatternObj)
                && valuePatternObj is ValuePattern valuePattern)
            {
                var text = valuePattern.Current.Value;
                if (!string.IsNullOrWhiteSpace(text)) values.Add(text);
            }
        }
        catch { }

        try
        {
            var name = element.Current.Name;
            if (!string.IsNullOrWhiteSpace(name)) values.Add(name);
        }
        catch { }
    }

    private static string ExtractCommand(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return "";
        var lines = Regex.Split(text.Replace("\0", ""), "\r?\n")
            .Select(line => line.TrimEnd())
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .ToArray();

        for (var index = lines.Length - 1; index >= 0; index--)
        {
            var candidate = ExtractCommandFromLine(lines[index]);
            if (!string.IsNullOrWhiteSpace(candidate)) return candidate;
        }
        return "";
    }

    private static string ExtractCommandFromLine(string line)
    {
        var value = line.Trim();
        if (value.Length == 0) return "";
        string[] patterns =
        {
            @"^(?:\([^)]+\)\s*)?PS\s+[^>]*>\s*(.+)$",
            @"^[A-Za-z]:\\[^>]*>\s*(.+)$",
            @"^\[[^\]]+\]\s*[#$]\s*(.+)$",
            @"^[^@\s]+@[^:\s]+:[^#$]*[#$]\s*(.+)$",
            @"^[#$]\s*(.+)$"
        };

        foreach (var pattern in patterns)
        {
            var match = Regex.Match(value, pattern);
            if (match.Success) return match.Groups[1].Value.Trim();
        }
        return value;
    }
}
