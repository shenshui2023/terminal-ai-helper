using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.ComponentModel;

namespace TerminalAi.Desktop;

internal sealed class CommandManagerForm : Form
{
    private readonly string _root;
    private readonly ProcessLauncher _launcher;
    private readonly ComboBox _toolFilter = new();
    private readonly TextBox _searchBox = new();
    private readonly DataGridView _grid = new();
    private readonly TextBox _toolBox = new();
    private readonly TextBox _commandBox = new();
    private readonly TextBox _summaryBox = new();
    private readonly TextBox _tagsBox = new();
    private readonly TextBox _urlBox = new();
    private readonly TextBox _importTextBox = new();
    private readonly TextBox _importUrlBox = new();
    private readonly Label _status = new();
    private readonly System.Windows.Forms.Timer _searchTimer = new();
    private readonly BindingSource _bindingSource = new();
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };
    private bool _isBindingGrid;
    private string _userCachePath = "";

    public CommandManagerForm(string root, ProcessLauncher launcher)
    {
        _root = root;
        _launcher = launcher;

        Text = "终端 AI 助手 - 命令缓存管理";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(1020, 680);
        Size = new Size(1280, 760);
        BackColor = Color.FromArgb(24, 26, 31);
        ForeColor = Color.FromArgb(232, 236, 243);
        Font = new Font("Microsoft YaHei UI", 9F);

        _searchTimer.Interval = 260;
        _searchTimer.Tick += (_, _) =>
        {
            _searchTimer.Stop();
            RefreshCommands();
        };

        Controls.Add(BuildLayout());
        Shown += (_, _) => BeginInvoke(new Action(RefreshCommands));
    }

    private Control BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(12),
            ColumnCount = 1,
            RowCount = 3
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));

        root.Controls.Add(BuildToolbar(), 0, 0);
        root.Controls.Add(BuildContent(), 0, 1);
        root.Controls.Add(_status, 0, 2);
        _status.Text = "正在准备命令管理页...";
        _status.TextAlign = ContentAlignment.MiddleLeft;
        _status.ForeColor = Color.FromArgb(180, 190, 205);
        return root;
    }

    private Control BuildToolbar()
    {
        var bar = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 6 };
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 70));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 170));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 70));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 94));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 94));

        bar.Controls.Add(MakeLabel("分类"), 0, 0);
        bar.Controls.Add(_toolFilter, 1, 0);
        bar.Controls.Add(MakeLabel("搜索"), 2, 0);
        bar.Controls.Add(_searchBox, 3, 0);
        bar.Controls.Add(MakeButton("刷新", RefreshCommands), 4, 0);
        bar.Controls.Add(MakeButton("关闭", Close), 5, 0);

        _toolFilter.DropDownStyle = ComboBoxStyle.DropDownList;
        _toolFilter.Items.AddRange(new object[] { "全部", "windows", "linux", "systemd", "k8s", "docker", "mysql", "git", "ssh", "npm", "python", "java", "adb", "custom" });
        _toolFilter.SelectedIndex = 0;
        _toolFilter.SelectedIndexChanged += (_, _) => RefreshCommands();
        _searchBox.TextChanged += (_, _) =>
        {
            _searchTimer.Stop();
            _searchTimer.Start();
        };
        Dark(_toolFilter);
        Dark(_searchBox);
        return bar;
    }

    private Control BuildContent()
    {
        var content = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1
        };
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 360));
        content.Controls.Add(BuildCategoryPanel(), 0, 0);
        content.Controls.Add(BuildGrid(), 1, 0);
        content.Controls.Add(BuildEditor(), 2, 0);
        return content;
    }

    private Control BuildCategoryPanel()
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 9, Padding = new Padding(0, 0, 10, 0) };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        for (var index = 1; index <= 6; index++) panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));

        panel.Controls.Add(MakeLabel("常用分类"), 0, 0);
        panel.Controls.Add(MakeToolButton("Windows", "windows"), 0, 1);
        panel.Controls.Add(MakeToolButton("Linux", "linux"), 0, 2);
        panel.Controls.Add(MakeToolButton("systemd", "systemd"), 0, 3);
        panel.Controls.Add(MakeToolButton("K8s", "k8s"), 0, 4);
        panel.Controls.Add(MakeToolButton("Docker", "docker"), 0, 5);
        panel.Controls.Add(MakeToolButton("DB/Git/SSH", "mysql"), 0, 6);
        panel.Controls.Add(MakeButton("打开缓存文件", OpenUserCache), 0, 8);
        return panel;
    }

    private Control BuildGrid()
    {
        _grid.Dock = DockStyle.Fill;
        _grid.AllowUserToAddRows = false;
        _grid.AllowUserToDeleteRows = false;
        _grid.ReadOnly = true;
        _grid.MultiSelect = false;
        _grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        _grid.BackgroundColor = Color.FromArgb(14, 16, 20);
        _grid.GridColor = Color.FromArgb(56, 60, 68);
        _grid.BorderStyle = BorderStyle.FixedSingle;
        _grid.AutoGenerateColumns = false;
        _grid.RowHeadersVisible = false;
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "分类", DataPropertyName = "Tool", Width = 70 });
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "命令", DataPropertyName = "Command", Width = 260 });
        _grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "说明", DataPropertyName = "Summary", AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill });
        _grid.DefaultCellStyle.BackColor = Color.FromArgb(18, 20, 24);
        _grid.DefaultCellStyle.ForeColor = Color.FromArgb(232, 236, 243);
        _grid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(0, 120, 212);
        _grid.DefaultCellStyle.SelectionForeColor = Color.White;
        _grid.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(31, 35, 43);
        _grid.ColumnHeadersDefaultCellStyle.ForeColor = Color.FromArgb(232, 236, 243);
        _grid.EnableHeadersVisualStyles = false;
        _grid.DataSource = _bindingSource;
        _grid.DataError += (_, e) =>
        {
            e.ThrowException = false;
            e.Cancel = true;
            _status.Text = "列表刷新时忽略了一次绑定错误，数据已重新加载。";
        };
        _grid.SelectionChanged += (_, _) => FillEditorFromSelection();
        return _grid;
    }

    private Control BuildEditor()
    {
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(10, 0, 0, 0),
            RowCount = 2
        };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 286));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.Controls.Add(BuildEditPanel(), 0, 0);
        panel.Controls.Add(BuildImportPanel(), 0, 1);
        return panel;
    }

    private Control BuildEditPanel()
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 8 };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
        for (var index = 1; index <= 5; index++) panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        panel.Controls.Add(MakeLabel("编辑用户命令"), 0, 0);
        panel.Controls.Add(MakeLabeledBox("分类", _toolBox), 0, 1);
        panel.Controls.Add(MakeLabeledBox("命令", _commandBox), 0, 2);
        panel.Controls.Add(MakeLabeledBox("说明", _summaryBox), 0, 3);
        panel.Controls.Add(MakeLabeledBox("标签", _tagsBox), 0, 4);
        panel.Controls.Add(MakeLabeledBox("来源 URL", _urlBox), 0, 5);
        panel.Controls.Add(BuildEditButtons(), 0, 6);
        return panel;
    }

    private Control BuildImportPanel()
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 6 };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 8));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));

        panel.Controls.Add(MakeLabel("从文档或官网提取命令"), 0, 0);
        panel.Controls.Add(MakeLabeledBox("官网 URL", _importUrlBox), 0, 1);
        panel.Controls.Add(MakeLabel("粘贴文档内容，或填写 URL 后点击提取。这个操作会调用中转站。"), 0, 2);
        _importTextBox.Multiline = true;
        _importTextBox.ScrollBars = ScrollBars.Vertical;
        _importTextBox.AcceptsReturn = true;
        _importTextBox.AcceptsTab = true;
        Dark(_importTextBox);
        panel.Controls.Add(_importTextBox, 0, 3);
        panel.Controls.Add(BuildImportButtons(), 0, 5);
        return panel;
    }

    private Control BuildEditButtons()
    {
        var buttons = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 4,
            RowCount = 1,
            Margin = new Padding(0),
            Padding = new Padding(0)
        };
        for (var index = 0; index < 4; index++)
        {
            buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
        }
        buttons.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        buttons.Controls.Add(MakeGridButton("新增/保存", SaveCommand), 0, 0);
        buttons.Controls.Add(MakeGridButton("删除", DeleteCommand), 1, 0);
        buttons.Controls.Add(MakeGridButton("复制命令", CopyCommand), 2, 0);
        buttons.Controls.Add(MakeGridButton("清空", ClearEditor), 3, 0);
        return buttons;
    }

    private static Button MakeGridButton(string text, Action action)
    {
        var button = MakeButton(text, action, fill: true);
        button.TextAlign = ContentAlignment.MiddleCenter;
        button.Margin = new Padding(2, 4, 2, 4);
        return button;
    }

    private Control BuildImportButtons()
    {
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        buttons.Controls.Add(MakeButton("中转站提取", ImportCommands));
        buttons.Controls.Add(MakeButton("查看全部", () =>
        {
            _toolFilter.SelectedIndex = 0;
            _searchBox.Clear();
            RefreshCommands();
        }));
        return buttons;
    }

    private Control MakeLabeledBox(string label, TextBox box)
    {
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 76));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.Controls.Add(MakeLabel(label), 0, 0);
        box.Dock = DockStyle.Fill;
        Dark(box);
        panel.Controls.Add(box, 1, 0);
        return panel;
    }

    private Button MakeToolButton(string text, string tool)
    {
        return MakeButton(text, () =>
        {
            var index = _toolFilter.Items.IndexOf(tool);
            if (index >= 0) _toolFilter.SelectedIndex = index;
        }, fill: true);
    }

    private static Label MakeLabel(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        ForeColor = Color.FromArgb(220, 225, 235)
    };

    private static Button MakeButton(string text, Action action, bool fill = false)
    {
        var button = new Button
        {
            Text = text,
            Width = 98,
            Height = 28,
            Dock = fill ? DockStyle.Fill : DockStyle.None,
            TextAlign = fill ? ContentAlignment.MiddleLeft : ContentAlignment.MiddleCenter,
            BackColor = Color.FromArgb(31, 35, 43),
            ForeColor = Color.FromArgb(232, 236, 243),
            FlatStyle = FlatStyle.Flat
        };
        button.FlatAppearance.BorderColor = Color.FromArgb(88, 92, 104);
        button.Click += (_, _) => action();
        return button;
    }

    private static void Dark(Control control)
    {
        control.BackColor = Color.FromArgb(11, 13, 16);
        control.ForeColor = Color.FromArgb(232, 236, 243);
    }

    private void RefreshCommands()
    {
        try
        {
            _status.Text = "正在读取本地命令缓存...";
            var selectedTool = _toolFilter.SelectedItem?.ToString() == "全部" ? "" : _toolFilter.SelectedItem?.ToString() ?? "";
            var query = _searchBox.Text.Trim();
            var all = LoadCommandEntries();
            var rows = FilterEntries(all, query, selectedTool).ToList();
            BindRows(rows);
            _status.Text = $"已加载 {rows.Count} 条命令。用户缓存：{_userCachePath}";
        }
        catch (Exception ex)
        {
            _status.Text = "加载失败：" + ex.Message;
        }
    }

    private void BindRows(List<CommandEntry> rows)
    {
        _isBindingGrid = true;
        try
        {
            _grid.SuspendLayout();
            _bindingSource.DataSource = new BindingList<CommandEntry>(rows);
            _grid.ClearSelection();
            if (rows.Count > 0 && _grid.Rows.Count > 0)
            {
                _grid.CurrentCell = _grid.Rows[0].Cells[0];
                _grid.Rows[0].Selected = true;
            }
        }
        finally
        {
            _grid.ResumeLayout();
            _isBindingGrid = false;
        }

        FillEditorFromSelection();
    }

    private List<CommandEntry> LoadCommandEntries()
    {
        _userCachePath = UserCachePath();
        var userEntries = ReadCacheFile(_userCachePath);
        var builtinEntries = ReadCacheFile(Path.Combine(_root, "src", "knowledge", "command-cache.json"));
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<CommandEntry>();
        foreach (var entry in userEntries.Concat(builtinEntries))
        {
            var key = NormalizeKey(entry.Command);
            if (key.Length == 0 || seen.Contains(key)) continue;
            seen.Add(key);
            result.Add(entry);
        }
        return result;
    }

    private static IEnumerable<CommandEntry> FilterEntries(IEnumerable<CommandEntry> entries, string query, string tool)
    {
        var q = query.Trim().ToLowerInvariant();
        var selectedTool = tool.Trim().ToLowerInvariant();
        return entries.Where(entry =>
        {
            if (selectedTool.Length > 0 && !string.Equals(entry.Tool, selectedTool, StringComparison.OrdinalIgnoreCase)) return false;
            if (q.Length == 0) return true;
            var haystack = $"{entry.Tool} {entry.Command} {entry.Summary} {entry.Tags}".ToLowerInvariant();
            return haystack.Contains(q);
        }).ToList();
    }

    private static List<CommandEntry> ReadCacheFile(string file)
    {
        if (!File.Exists(file)) return new List<CommandEntry>();
        var info = new FileInfo(file);
        if (info.Length > 100 * 1024 * 1024)
        {
            throw new InvalidOperationException("命令缓存文件超过 100MB，请拆分或清理后再加载。");
        }
        using var doc = JsonDocument.Parse(File.ReadAllText(file, Encoding.UTF8));
        if (!doc.RootElement.TryGetProperty("commands", out var commands) || commands.ValueKind != JsonValueKind.Array)
        {
            return new List<CommandEntry>();
        }
        return commands.EnumerateArray().Select(CommandEntry.FromJson).Where(entry => !string.IsNullOrWhiteSpace(entry.Command)).ToList();
    }

    private void FillEditorFromSelection()
    {
        if (_isBindingGrid) return;
        if (_grid.CurrentRow?.DataBoundItem is not CommandEntry row) return;
        _toolBox.Text = row.Tool;
        _commandBox.Text = row.Command;
        _summaryBox.Text = row.Summary;
        _tagsBox.Text = row.Tags;
        _urlBox.Text = row.SourceUrl;
    }

    private void SaveCommand()
    {
        try
        {
            var command = _commandBox.Text.Trim();
            var summary = _summaryBox.Text.Trim();
            if (command.Length == 0 || summary.Length == 0)
            {
                _status.Text = "命令和说明不能为空。";
                return;
            }

            var userEntries = ReadCacheFile(UserCachePath());
            var key = NormalizeKey(command);
            userEntries.RemoveAll(entry => string.Equals(NormalizeKey(entry.Command), key, StringComparison.OrdinalIgnoreCase));
            userEntries.Insert(0, new CommandEntry
            {
                Tool = string.IsNullOrWhiteSpace(_toolBox.Text) ? "custom" : _toolBox.Text.Trim(),
                Command = command,
                Summary = summary,
                Tags = _tagsBox.Text.Trim(),
                Source = "user",
                SourceUrl = _urlBox.Text.Trim()
            });
            WriteUserCache(userEntries);
            RefreshCommands();
            _status.Text = "已保存用户命令。";
        }
        catch (Exception ex)
        {
            _status.Text = "保存失败：" + ex.Message;
        }
    }

    private void DeleteCommand()
    {
        if (string.IsNullOrWhiteSpace(_commandBox.Text)) return;
        try
        {
            var key = NormalizeKey(_commandBox.Text);
            var userEntries = ReadCacheFile(UserCachePath());
            var removed = userEntries.RemoveAll(entry => string.Equals(NormalizeKey(entry.Command), key, StringComparison.OrdinalIgnoreCase));
            WriteUserCache(userEntries);
            RefreshCommands();
            _status.Text = removed > 0 ? "已删除用户命令。" : "这是内置命令，不能删除；可以新增同名用户命令覆盖。";
        }
        catch (Exception ex)
        {
            _status.Text = "删除失败：" + ex.Message;
        }
    }

    private void CopyCommand()
    {
        if (!string.IsNullOrWhiteSpace(_commandBox.Text))
        {
            Clipboard.SetText(_commandBox.Text);
            _status.Text = "命令已复制。";
        }
    }

    private void ClearEditor()
    {
        _toolBox.Text = "custom";
        _commandBox.Clear();
        _summaryBox.Clear();
        _tagsBox.Clear();
        _urlBox.Clear();
    }

    private async void ImportCommands()
    {
        try
        {
            _status.Text = "正在调用中转站提取命令，请稍等...";
            var temp = Path.GetTempFileName();
            await File.WriteAllTextAsync(temp, _importTextBox.Text, Encoding.UTF8);
            await Task.Run(() => RunTaih("commands", "import", "--from-file", temp, "--url", _importUrlBox.Text, "--tool", string.IsNullOrWhiteSpace(_toolBox.Text) ? "custom" : _toolBox.Text));
            try { File.Delete(temp); } catch { }
            RefreshCommands();
            _status.Text = "已从文档提取并导入命令。";
        }
        catch (Exception ex)
        {
            _status.Text = "导入失败：" + ex.Message;
        }
    }

    private void OpenUserCache()
    {
        var file = UserCachePath();
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
        if (!File.Exists(file)) WriteUserCache(new List<CommandEntry>());
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("notepad.exe", file) { UseShellExecute = true });
    }

    private void WriteUserCache(List<CommandEntry> entries)
    {
        var file = UserCachePath();
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
        File.WriteAllText(file, JsonSerializer.Serialize(new CommandCacheFile { Version = 1, Commands = entries }, _jsonOptions) + Environment.NewLine, Encoding.UTF8);
    }

    private static string NormalizeKey(string value)
    {
        return string.Join(" ", value.Trim().ToLowerInvariant().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    private static string UserCachePath()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(home, ".terminal-ai-helper", "command-cache.user.json");
    }

    private string RunTaih(params string[] args)
    {
        var all = new[] { Path.Combine(_root, "bin", "taih.js") }.Concat(args);
        return _launcher.RunCapture("node.exe", all, timeoutMs: 180000);
    }

    private sealed class CommandCacheFile
    {
        [JsonPropertyName("version")]
        public int Version { get; init; } = 1;

        [JsonPropertyName("commands")]
        public List<CommandEntry> Commands { get; init; } = new();
    }

    private sealed class CommandEntry
    {
        public string Tool { get; init; } = "";
        public string Command { get; init; } = "";
        public string Summary { get; init; } = "";
        public string Source { get; init; } = "";
        public string SourceUrl { get; init; } = "";
        public string Tags { get; init; } = "";
        public string[] Aliases { get; init; } = Array.Empty<string>();

        public static CommandEntry FromJson(JsonElement item)
        {
            return new CommandEntry
            {
                Tool = Get(item, "tool"),
                Command = Get(item, "command"),
                Summary = Get(item, "summary"),
                Source = Get(item, "source"),
                SourceUrl = Get(item, "sourceUrl"),
                Aliases = ReadArray(item, "aliases"),
                Tags = string.Join(",", ReadArray(item, "tags"))
            };
        }

        private static string Get(JsonElement item, string name)
        {
            return item.TryGetProperty(name, out var value) ? value.GetString() ?? "" : "";
        }

        private static string[] ReadArray(JsonElement item, string name)
        {
            if (!item.TryGetProperty(name, out var values) || values.ValueKind != JsonValueKind.Array) return Array.Empty<string>();
            return values.EnumerateArray().Select(value => value.GetString()).Where(value => !string.IsNullOrWhiteSpace(value)).Cast<string>().ToArray();
        }
    }
}
