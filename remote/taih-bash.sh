# terminal-ai-helper remote bash integration.
# Use with a reverse tunnel from your local machine:
#   ssh -R 17888:127.0.0.1:17888 <user>@<host>

export TAIH_REMOTE_URL="${TAIH_REMOTE_URL:-http://127.0.0.1:17888/api}"

_taih_post() {
  TAIH_MODE="$1" TAIH_FORMAT="${2:-text}" TAIH_TEXT="$3" python3 - <<'PY'
import json
import os
import sys
import urllib.request

payload = json.dumps({
    "mode": os.environ.get("TAIH_MODE", "explain"),
    "format": os.environ.get("TAIH_FORMAT", "text"),
    "text": os.environ.get("TAIH_TEXT", ""),
    "source": "ssh-readline",
    "shell": os.environ.get("SHELL", "remote shell")
}).encode("utf-8")

req = urllib.request.Request(
    os.environ.get("TAIH_REMOTE_URL", "http://127.0.0.1:17888/api"),
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

taih() {
  local mode="${1:-explain}"
  shift || true
  local text="$*"
  if [ -z "$text" ]; then
    text="${READLINE_LINE:-}"
  fi
  _taih_post "$mode" text "$text"
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

_taih_readline_complete() {
  local completion
  completion="$(_taih_post complete raw "$READLINE_LINE")"
  if [ -n "$completion" ]; then
    READLINE_LINE="${READLINE_LINE}${completion}"
    READLINE_POINT=${#READLINE_LINE}
  fi
}

bind -x '"\e/":_taih_readline_explain'
bind -x '"\e[1;3F":_taih_readline_fix'
bind -x '"\C- ":_taih_readline_complete'

echo "terminal-ai-helper remote loaded: Alt+/ explain, Alt+F fix, Ctrl+Space complete"
