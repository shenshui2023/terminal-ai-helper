namespace TerminalAi.Desktop;

internal sealed class TerminalAiDesktopActions
{
    private readonly TerminalCaptureService _terminal;
    private readonly PowerShellBridge _bridge;
    private readonly Action<string> _notify;

    public TerminalAiDesktopActions(TerminalCaptureService terminal, PowerShellBridge bridge, Action<string> notify)
    {
        _terminal = terminal;
        _bridge = bridge;
        _notify = notify;
    }

    public void OpenPanel() => _bridge.OpenPanel();

    public void OpenSshPanel() => _bridge.OpenSshPanel();

    public void ExplainSelectedText() => OpenSelectedText("explain");

    public void FixSelectedText() => OpenSelectedText("fix");

    public void ExplainForegroundCommand() => OpenForegroundCommand("explain");

    public void FixForegroundCommand() => OpenForegroundCommand("fix");

    public void CompleteForegroundCommand()
    {
        var context = GetContextOrNotify();
        if (context is null) return;
        var choice = _bridge.ShowCompletionPopup(context.Command);
        if (string.IsNullOrWhiteSpace(choice)) return;
        try
        {
            _terminal.ReplaceCurrentCommand(context.Handle, context.Command, choice);
        }
        catch (Exception ex)
        {
            _notify("写回终端失败：" + ex.Message);
        }
    }

    private void OpenSelectedText(string mode)
    {
        SendKeys.SendWait("^c");
        Thread.Sleep(220);
        var text = Clipboard.GetText();
        if (string.IsNullOrWhiteSpace(text))
        {
            _notify("没有读取到选中文本。请先在终端里选中命令或报错。");
            return;
        }
        _bridge.OpenPanel(text, mode, NativeMethods.GetForegroundWindow());
    }

    private void OpenForegroundCommand(string mode)
    {
        var context = GetContextOrNotify();
        if (context is null) return;
        _bridge.OpenPanel(context.Command, mode, context.Handle);
    }

    private TerminalContext? GetContextOrNotify()
    {
        var context = _terminal.GetForegroundContext();
        if (!string.IsNullOrWhiteSpace(context.Command)) return context;

        var message = "没有从当前终端窗口读取到正在输入的命令。请点回 Windows Terminal 后重试。";
        if (!string.IsNullOrWhiteSpace(context.Error)) message += " " + context.Error;
        _notify(message);
        return null;
    }
}
