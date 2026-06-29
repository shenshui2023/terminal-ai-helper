namespace TerminalAi.Desktop;

internal sealed class TerminalAiApplicationContext : ApplicationContext
{
    private const int HotKeyExplainSelection = 101;
    private const int HotKeyFixSelection = 102;
    private const int HotKeyExplainTerminal = 103;
    private const int HotKeyCompleteTerminal = 104;

    private readonly NotifyIcon _notify;
    private readonly GlobalHotKeyWindow _hotKeys;
    private readonly LocalServerManager _server;
    private System.Windows.Forms.Timer? _startupTimer;

    public TerminalAiApplicationContext(string root, bool openCommandManager = false)
    {
        var launcher = new ProcessLauncher(root);
        var bridge = new PowerShellBridge(root, launcher);
        var terminal = new TerminalCaptureService();
        _server = new LocalServerManager(root, launcher);
        var actions = new TerminalAiDesktopActions(terminal, bridge, ShowTip);

        _notify = new NotifyIcon
        {
            Icon = SystemIcons.Information,
            Text = "终端 AI 助手",
            Visible = true,
            ContextMenuStrip = BuildMenu(actions, root, launcher)
        };
        _notify.DoubleClick += (_, _) => actions.OpenPanel();

        _hotKeys = new GlobalHotKeyWindow();
        RegisterHotKeys(actions);
        ShowTip("桌面端已启动：Ctrl+Alt+P 补全当前终端输入，Ctrl+Alt+E 解释当前输入。");
        if (openCommandManager)
        {
            _startupTimer = new System.Windows.Forms.Timer { Interval = 250 };
            _startupTimer.Tick += (_, _) =>
            {
                _startupTimer?.Stop();
                new CommandManagerForm(root, launcher).Show();
            };
            _startupTimer.Start();
        }
    }

    private ContextMenuStrip BuildMenu(TerminalAiDesktopActions actions, string root, ProcessLauncher launcher)
    {
        var menu = new ContextMenuStrip();
        Add(menu, "打开管理面板", actions.OpenPanel);
        Add(menu, "管理命令缓存", () => new CommandManagerForm(root, launcher).Show());
        Add(menu, "打开 SSH 面板", actions.OpenSshPanel);
        menu.Items.Add(new ToolStripSeparator());
        Add(menu, "解释当前终端输入（Ctrl+Alt+E）", actions.ExplainForegroundCommand);
        Add(menu, "补全当前终端输入（Ctrl+Alt+P）", actions.CompleteForegroundCommand);
        Add(menu, "解释选中文本（Ctrl+Alt+/）", actions.ExplainSelectedText);
        Add(menu, "诊断选中文本（Ctrl+Alt+F）", actions.FixSelectedText);
        menu.Items.Add(new ToolStripSeparator());
        Add(menu, "启动本地 helper server", () =>
        {
            _server.Start(replace: true);
            ShowTip("本地 helper server 已启动。");
        });
        Add(menu, "停止本地 helper server", () =>
        {
            _server.Stop();
            ShowTip("本地 helper server 已停止。");
        });
        menu.Items.Add(new ToolStripSeparator());
        Add(menu, "退出", ExitThread);
        return menu;
    }

    private static void Add(ContextMenuStrip menu, string text, Action action)
    {
        var item = menu.Items.Add(text);
        item.Click += (_, _) => action();
    }

    private void RegisterHotKeys(TerminalAiDesktopActions actions)
    {
        var ctrlAlt = NativeMethods.ModControl | NativeMethods.ModAlt;
        SafeRegisterHotKey(HotKeyExplainSelection, ctrlAlt, NativeMethods.VkOem2, "Ctrl+Alt+/", actions.ExplainSelectedText);
        SafeRegisterHotKey(HotKeyFixSelection, ctrlAlt, NativeMethods.VkF, "Ctrl+Alt+F", actions.FixSelectedText);
        SafeRegisterHotKey(HotKeyExplainTerminal, ctrlAlt, NativeMethods.VkE, "Ctrl+Alt+E", actions.ExplainForegroundCommand);
        SafeRegisterHotKey(HotKeyCompleteTerminal, ctrlAlt, NativeMethods.VkP, "Ctrl+Alt+P", actions.CompleteForegroundCommand);
    }

    private void SafeRegisterHotKey(int id, uint modifiers, int key, string label, Action action)
    {
        try
        {
            _hotKeys.Register(id, modifiers, key, action);
        }
        catch (Exception ex)
        {
            ShowTip($"{label} 注册失败，可能被其他软件占用：{ex.Message}");
        }
    }

    private void ShowTip(string text)
    {
        _notify.BalloonTipTitle = "终端 AI 助手";
        _notify.BalloonTipText = text;
        _notify.ShowBalloonTip(2500);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _hotKeys.Dispose();
            _server.Dispose();
            _startupTimer?.Dispose();
            _notify.Visible = false;
            _notify.Dispose();
        }
        base.Dispose(disposing);
    }
}
