# terminal-ai-helper remote bash integration.
# Use with a reverse tunnel from your local machine:
#   ssh -R 17888:127.0.0.1:17888 <user>@<host>

export TAIH_REMOTE_URL="${TAIH_REMOTE_URL:-http://127.0.0.1:17888/api}"
export TAIH_REMOTE_PANEL_URL="${TAIH_REMOTE_PANEL_URL:-http://127.0.0.1:17888/panel}"
export TAIH_REMOTE_COMPLETE_POPUP_URL="${TAIH_REMOTE_COMPLETE_POPUP_URL:-http://127.0.0.1:17888/complete-popup}"
export TAIH_REMOTE_TOOLS="${TAIH_REMOTE_TOOLS:-linux,ssh,systemd,k8s,docker,git}"
export TAIH_REMOTE_STYLE="${TAIH_REMOTE_STYLE:-standard}"
export TAIH_REMOTE_COMPLETE_POPUP="${TAIH_REMOTE_COMPLETE_POPUP:-1}"

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

_taih_complete_popup() {
  TAIH_TEXT="$1" TAIH_ENDPOINT="$TAIH_REMOTE_COMPLETE_POPUP_URL" python3 - <<'PY'
import json
import os
import socket
import sys
import urllib.request

payload = json.dumps({
    "mode": "complete",
    "format": "json",
    "text": os.environ.get("TAIH_TEXT", ""),
    "tools": os.environ.get("TAIH_REMOTE_TOOLS", "linux,ssh,systemd,k8s,docker,git"),
    "style": os.environ.get("TAIH_REMOTE_STYLE", "brief"),
    "noDialog": os.environ.get("TAIH_REMOTE_COMPLETE_POPUP_NO_DIALOG", "") == "1",
    "waitAi": os.environ.get("TAIH_REMOTE_COMPLETE_POPUP_WAIT_AI", "") == "1",
    "source": "ssh-readline-complete-popup",
    "shell": os.environ.get("SHELL", "remote shell"),
    "host": socket.gethostname(),
    "session": "%s:%s" % (socket.gethostname(), os.environ.get("USER", "remote"))
}).encode("utf-8")

req = urllib.request.Request(
    os.environ.get("TAIH_ENDPOINT", "http://127.0.0.1:17888/complete-popup"),
    data=payload,
    headers={"content-type": "application/json"},
    method="POST"
)

try:
    with urllib.request.urlopen(req, timeout=600) as resp:
        raw = resp.read().decode("utf-8")
    data = json.loads(raw)
    if data.get("ok") and data.get("completion"):
        sys.stdout.write(str(data["completion"]))
    elif data.get("source") == "cancelled" or data.get("error") == "cancelled":
        sys.stdout.write("__TAIH_CANCELLED__")
except Exception:
    pass
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
  _taih_post tools text "Generate a remote command menu for the selected tools."
  printf '\n'
}

taih-predict() {
  local text
  text="$(_taih_collect_text "$@")"
  _taih_post complete text "$text"
  printf '\n'
}

taih-complete-popup() {
  local text
  text="$(_taih_collect_text "$@")"
  local completion
  completion="$(_taih_complete_popup "$text")"
  if [ "$completion" = "__TAIH_CANCELLED__" ]; then
    printf 'terminal-ai-helper: completion popup cancelled\n' >&2
    return 130
  fi
  if [ -n "$completion" ]; then
    printf '%s\n' "$completion"
  else
    printf 'terminal-ai-helper: local completion popup returned no command\n' >&2
    return 1
  fi
}

_taih_apply_completion() {
  local completion="$1"
  if [ -z "$completion" ]; then
    return 1
  fi
  if [ -z "$READLINE_LINE" ] || [[ "$completion" == "$READLINE_LINE"* ]]; then
    READLINE_LINE="$completion"
  elif [[ "$completion" == *"$READLINE_LINE"* ]]; then
    READLINE_LINE="$completion"
  else
    READLINE_LINE="${READLINE_LINE} ${completion}"
  fi
  READLINE_POINT=${#READLINE_LINE}
  return 0
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
  local completion=""
  if [ "$TAIH_REMOTE_COMPLETE_POPUP" != "0" ]; then
    completion="$(_taih_complete_popup "$READLINE_LINE")"
  fi
  if [ "$completion" = "__TAIH_CANCELLED__" ]; then
    return 0
  fi
  if [ -z "$completion" ]; then
    completion="$(_taih_post complete raw "$READLINE_LINE")"
  fi
  _taih_apply_completion "$completion"
}

_taih_readline_tools() {
  printf '\n'
  _taih_post tools json "Generate a remote command menu for the selected tools." "$TAIH_REMOTE_PANEL_URL" >/dev/null
  printf 'terminal-ai-helper: opened local tools menu\n'
}

taih-keys() {
  echo "terminal-ai-helper remote key status:"
  echo "  shell: ${SHELL:-unknown}"
  echo "  bash: ${BASH_VERSION:-not bash}"
  echo "  api: ${TAIH_REMOTE_URL}"
  echo "  panel: ${TAIH_REMOTE_PANEL_URL}"
  echo "  completionPopup: ${TAIH_REMOTE_COMPLETE_POPUP_URL}"
  echo "  popupEnabled: ${TAIH_REMOTE_COMPLETE_POPUP}"
  echo "  tools: ${TAIH_REMOTE_TOOLS}"
  echo "  shortcuts:"
  echo "    Alt+/        explain current remote command"
  echo "    Alt+?        open local Windows panel"
  echo "    Alt+T        open tools menu"
  echo "    Alt+F or Alt+f diagnose current remote command"
  echo "    Ctrl+Space   open local desktop completion popup"
  echo "  commands:"
  echo "    taih explain <text>             analyze text or current line"
  echo "    taih complete <prefix>          predict command candidates"
  echo "    taih-complete-popup <prefix>    open local desktop completion popup"
  echo "    taih-panel explain              open local Windows panel"
  echo "    taih-tools [toolset]            show or change remote toolset"
  bind -X 2>/dev/null | grep _taih || true
}

if [ -n "${BASH_VERSION:-}" ] && [[ $- == *i* ]]; then
  bind -x '"\e/":_taih_readline_explain'
  bind -x '"\e?":_taih_readline_panel'
  bind -x '"\et":_taih_readline_tools'
  bind -x '"\eT":_taih_readline_tools'
  bind -x '"\ef":_taih_readline_fix'
  bind -x '"\eF":_taih_readline_fix'
  bind -x '"\e[1;3F":_taih_readline_fix'
  bind -x '"\C- ":_taih_readline_complete'
else
  echo "terminal-ai-helper remote warning: shortcuts require interactive bash/readline; use taih/taih-panel commands instead"
fi

echo "terminal-ai-helper remote loaded: Alt+/ explain, Alt+? local panel, Alt+T tools, Alt+F fix, Ctrl+Space local popup complete. Run taih-keys to diagnose."
