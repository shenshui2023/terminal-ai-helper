# terminal-ai-helper remote bash integration.
# Use with a reverse tunnel from your local machine:
#   ssh -R 17888:127.0.0.1:17888 <user>@<host>

export TAIH_REMOTE_URL="${TAIH_REMOTE_URL:-http://127.0.0.1:17888/api}"
export TAIH_REMOTE_PANEL_URL="${TAIH_REMOTE_PANEL_URL:-http://127.0.0.1:17888/panel}"
export TAIH_REMOTE_TOOLS="${TAIH_REMOTE_TOOLS:-linux,ssh,systemd,k8s,docker,git}"
export TAIH_REMOTE_STYLE="${TAIH_REMOTE_STYLE:-standard}"

_taih_post() {
  TAIH_MODE="$1" TAIH_FORMAT="${2:-text}" TAIH_TEXT="$3" TAIH_ENDPOINT="${4:-$TAIH_REMOTE_URL}" python3 - <<'PY'
import json
import os
import socket
import sys
import urllib.request

payload = json.dumps({
    "mode": os.environ.get("TAIH_MODE", "explain"),
    "format": os.environ.get("TAIH_FORMAT", "text"),
    "text": os.environ.get("TAIH_TEXT", ""),
    "tools": os.environ.get("TAIH_REMOTE_TOOLS", "linux,ssh,systemd,k8s,docker,git"),
    "style": os.environ.get("TAIH_REMOTE_STYLE", "standard"),
    "source": "ssh-readline",
    "shell": os.environ.get("SHELL", "remote shell"),
    "host": socket.gethostname(),
    "session": "%s:%s" % (socket.gethostname(), os.environ.get("USER", "remote"))
}).encode("utf-8")

req = urllib.request.Request(
    os.environ.get("TAIH_ENDPOINT") or os.environ.get("TAIH_REMOTE_URL", "http://127.0.0.1:17888/api"),
    data=payload,
    headers={"content-type": "application/json"},
    method="POST"
)

try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        sys.stdout.write(resp.read().decode("utf-8"))
except Exception as exc:
    sys.stdout.write("terminal-ai-helper remote request failed: %s" % exc)
PY
}

_taih_collect_text() {
  local text="$*"
  if [ -z "$text" ] && [ ! -t 0 ]; then
    text="$(cat)"
  fi
  if [ -z "$text" ]; then
    text="${READLINE_LINE:-}"
  fi
  printf '%s' "$text"
}

taih() {
  local mode="${1:-explain}"
  shift || true
  local text
  text="$(_taih_collect_text "$@")"
  _taih_post "$mode" text "$text"
  printf '\n'
}

taih-panel() {
  local mode="${1:-explain}"
  shift || true
  local text
  text="$(_taih_collect_text "$@")"
  _taih_post "$mode" json "$text" "$TAIH_REMOTE_PANEL_URL" >/dev/null
  printf 'terminal-ai-helper: opened local panel for remote %s\n' "$mode"
}

taih-tools() {
  if [ "$#" -gt 0 ]; then
    export TAIH_REMOTE_TOOLS="$*"
    printf 'terminal-ai-helper: remote tools = %s\n' "$TAIH_REMOTE_TOOLS"
    return 0
  fi
  printf 'terminal-ai-helper remote tools: %s\n' "$TAIH_REMOTE_TOOLS"
  _taih_post tools text "生成远端常用工具菜单"
  printf '\n'
}

taih-predict() {
  local text
  text="$(_taih_collect_text "$@")"
  _taih_post complete text "$text"
  printf '\n'
}

_taih_readline_explain() {
  printf '\n'
  _taih_post explain text "$READLINE_LINE"
  printf '\n'
}

_taih_readline_fix() {
  printf '\n'
  _taih_post fix text "$READLINE_LINE"
  printf '\n'
}

_taih_readline_panel() {
  printf '\n'
  _taih_post explain json "$READLINE_LINE" "$TAIH_REMOTE_PANEL_URL" >/dev/null
  printf 'terminal-ai-helper: opened local panel\n'
}

_taih_readline_complete() {
  local completion
  completion="$(_taih_post complete raw "$READLINE_LINE")"
  if [ -n "$completion" ]; then
    if [ -z "$READLINE_LINE" ] || [[ "$completion" == "$READLINE_LINE"* ]]; then
      READLINE_LINE="$completion"
    elif [[ "$completion" == *"$READLINE_LINE"* ]]; then
      READLINE_LINE="$completion"
    else
      READLINE_LINE="${READLINE_LINE} ${completion}"
    fi
    READLINE_POINT=${#READLINE_LINE}
  fi
}

_taih_readline_tools() {
  printf '\n'
  _taih_post tools json "生成远端常用工具菜单" "$TAIH_REMOTE_PANEL_URL" >/dev/null
  printf 'terminal-ai-helper: opened local tools menu\n'
}

taih-keys() {
  echo "terminal-ai-helper remote key status:"
  echo "  shell: ${SHELL:-unknown}"
  echo "  bash: ${BASH_VERSION:-not bash}"
  echo "  api: ${TAIH_REMOTE_URL}"
  echo "  panel: ${TAIH_REMOTE_PANEL_URL}"
  echo "  tools: ${TAIH_REMOTE_TOOLS}"
  echo "  shortcuts:"
  echo "    Alt+/        explain current remote command"
  echo "    Alt+?        open local Windows panel"
  echo "    Alt+T        open tools menu"
  echo "    Alt+F or Alt+f diagnose current remote command"
  echo "    Ctrl+Space   complete current remote command"
  echo "  commands:"
  echo "    taih explain <text>     analyze text or current line"
  echo "    taih complete <prefix>  predict command candidates"
  echo "    taih-panel explain      open local Windows panel"
  echo "    taih-tools [toolset]    show or change remote toolset"
  bind -X 2>/dev/null | grep _taih || true
}

if [ -n "${BASH_VERSION:-}" ]; then
  bind -x '"\e/":_taih_readline_explain'
  bind -x '"\e?":_taih_readline_panel'
  bind -x '"\et":_taih_readline_tools'
  bind -x '"\eT":_taih_readline_tools'
  bind -x '"\ef":_taih_readline_fix'
  bind -x '"\eF":_taih_readline_fix'
  bind -x '"\e[1;3F":_taih_readline_fix'
  bind -x '"\C- ":_taih_readline_complete'
else
  echo "terminal-ai-helper remote warning: shortcuts require interactive bash; use taih/taih-panel commands instead"
fi

echo "terminal-ai-helper remote loaded: Alt+/ explain, Alt+? local panel, Alt+T tools, Alt+F fix, Ctrl+Space complete. Run taih-keys to diagnose."
