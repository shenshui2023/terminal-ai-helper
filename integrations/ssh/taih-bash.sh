# terminal-ai-helper remote bash integration.
# Use with a reverse tunnel from your local machine:
#   ssh -R 17888:127.0.0.1:17888 <user>@<host>

export TAIH_REMOTE_URL="${TAIH_REMOTE_URL:-http://127.0.0.1:17888/api}"
export TAIH_REMOTE_PANEL_URL="${TAIH_REMOTE_PANEL_URL:-http://127.0.0.1:17888/panel}"

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
    READLINE_LINE="${READLINE_LINE}${completion}"
    READLINE_POINT=${#READLINE_LINE}
  fi
}

taih-keys() {
  echo "terminal-ai-helper remote key status:"
  echo "  shell: ${SHELL:-unknown}"
  echo "  bash: ${BASH_VERSION:-not bash}"
  echo "  api: ${TAIH_REMOTE_URL}"
  echo "  panel: ${TAIH_REMOTE_PANEL_URL}"
  echo "  shortcuts:"
  echo "    Alt+/        explain current remote command"
  echo "    Alt+?        open local Windows panel"
  echo "    Alt+F or Alt+f diagnose current remote command"
  echo "    Ctrl+Space   complete current remote command"
  bind -X 2>/dev/null | grep _taih || true
}

if [ -n "${BASH_VERSION:-}" ]; then
  bind -x '"\e/":_taih_readline_explain'
  bind -x '"\e?":_taih_readline_panel'
  bind -x '"\ef":_taih_readline_fix'
  bind -x '"\eF":_taih_readline_fix'
  bind -x '"\e[1;3F":_taih_readline_fix'
  bind -x '"\C- ":_taih_readline_complete'
else
  echo "terminal-ai-helper remote warning: shortcuts require interactive bash; use taih/taih-panel commands instead"
fi

echo "terminal-ai-helper remote loaded: Alt+/ explain, Alt+? local panel, Alt+F fix, Ctrl+Space complete. Run taih-keys to diagnose."
