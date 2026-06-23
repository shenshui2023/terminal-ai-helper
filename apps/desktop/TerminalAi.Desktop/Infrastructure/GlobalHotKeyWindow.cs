namespace TerminalAi.Desktop;

internal sealed class GlobalHotKeyWindow : NativeWindow, IDisposable
{
    private readonly Dictionary<int, Action> _handlers = new();

    public GlobalHotKeyWindow()
    {
        CreateHandle(new CreateParams());
    }

    public void Register(int id, uint modifiers, int key, Action handler)
    {
        if (!NativeMethods.RegisterHotKey(Handle, id, modifiers, key))
        {
            throw new InvalidOperationException($"注册全局快捷键失败：id={id}");
        }
        _handlers[id] = handler;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == NativeMethods.WmHotKey && _handlers.TryGetValue(m.WParam.ToInt32(), out var handler))
        {
            handler();
            return;
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        foreach (var id in _handlers.Keys.ToArray())
        {
            NativeMethods.UnregisterHotKey(Handle, id);
        }
        _handlers.Clear();
        DestroyHandle();
    }
}
