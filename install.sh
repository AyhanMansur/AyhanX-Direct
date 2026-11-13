#!/usr/bin/env bash
# ============================================================================
#   AyhanX-Agent · terminal + web client for cloud & local LLMs
#   Repository:  https://github.com/AyhanMansur/AyhanX-Agent
#   Version:     4.0.0
#
#   Usage:
#     ./ai.sh                    chat (terminal)
#     ./ai.sh web [port]         launch web UI at http://localhost:8080
#     ./ai.sh switch <name>      switch provider and exit
#     ./ai.sh ask "prompt"       one-shot answer
#     ./ai.sh health             test the API connection
#     ./ai.sh config             show file locations
#     ./ai.sh version            print version
# ============================================================================
set -euo pipefail

VERSION="4.0.0"
REPO_URL="https://github.com/AyhanMansur/AyhanX-Agent"
APP_DIR="${HOME}/.ai_platform"
VENV="${APP_DIR}/.venv"
RUNNER_DIR="${APP_DIR}/runner"
CONFIG_FILE="${APP_DIR}/config.json"
ENV_FILE="${APP_DIR}/.env"
HISTORY_FILE="${APP_DIR}/history.txt"
CHATS_DIR="${APP_DIR}/chats"
LOG_FILE="${APP_DIR}/install.log"
PROVIDER_FILE="${APP_DIR}/provider"
PROVIDERS_FILE="${APP_DIR}/providers.json"
export AI_RUNNER_VERSION="$VERSION"

# ---------- palette ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  E=$'\e'
  V1="${E}[38;5;44m"; V2="${E}[38;5;30m"; C1="${E}[38;5;51m"
  PK="${E}[38;5;213m"; GD="${E}[38;5;221m"; MT="${E}[38;5;245m"
  OK="${E}[38;5;84m"; ER="${E}[38;5;203m"
  BD="${E}[1m"; DM="${E}[2m"; RS="${E}[0m"
else
  E= V1= V2= C1= PK= GD= MT= OK= ER= BD= DM= RS=
fi

cleanup() {
  local code=$?
  printf '%s' "$RS" 2>/dev/null || true
  stty sane 2>/dev/null || true
  exit "$code"
}
trap cleanup EXIT INT TERM

# ============================================================================
#  PROVIDER HELPERS
# ============================================================================
is_local_provider() {
  case "$1" in
    ollama|lmstudio|vllm|llamacpp|localai) return 0 ;;
    *) return 1 ;;
  esac
}

provider_of_key() {
  case "${1:-}" in
    sk-or-*)  echo "openrouter" ;;
    gsk_*)    echo "groq" ;;
    sk-*)     echo "deepseek" ;;
    AIza*|AQ.*) echo "google" ;;
    *)        echo "" ;;
  esac
}

provider_url() {
  case "$1" in
    openrouter) echo "https://openrouter.ai/api/v1" ;;
    groq)       echo "https://api.groq.com/openai/v1" ;;
    google)     echo "https://generativelanguage.googleapis.com/v1beta/openai" ;;
    ollama)     echo "${OLLAMA_URL:-http://localhost:11434/v1}" ;;
    lmstudio)   echo "${LMSTUDIO_URL:-http://localhost:1234/v1}" ;;
    vllm)       echo "${VLLM_URL:-http://localhost:8000/v1}" ;;
    llamacpp)   echo "${LLAMACPP_URL:-http://localhost:8080/v1}" ;;
    localai)    echo "${LOCALAI_URL:-http://localhost:8080/v1}" ;;
    *)          echo "https://api.deepseek.com" ;;
  esac
}

provider_default_model() {
  case "$1" in
    openrouter) echo "deepseek/deepseek-chat" ;;
    groq)       echo "llama-3.3-70b-versatile" ;;
    google)     echo "gemini-2.5-flash" ;;
    ollama)     echo "qwen2.5:3b" ;;
    lmstudio|vllm|llamacpp|localai) echo "local-model" ;;
    *)          echo "deepseek-chat" ;;
  esac
}

provider_label() {
  case "$1" in
    openrouter) echo "OpenRouter" ;;
    groq)       echo "Groq" ;;
    google)     echo "Google AI Studio" ;;
    ollama)     echo "Ollama" ;;
    lmstudio)   echo "LM Studio" ;;
    vllm)       echo "vLLM" ;;
    llamacpp)   echo "llama.cpp" ;;
    localai)    echo "LocalAI" ;;
    *)          echo "DeepSeek" ;;
  esac
}

probe_local() {
  local url="$1"
  timeout 2 curl -sSf -H "Authorization: Bearer local" \
    "${url%/}/models" 2>/dev/null | grep -q '"id"'
}

detect_local() {
  local pair name url
  for pair in \
    "ollama:${OLLAMA_URL:-http://localhost:11434/v1}" \
    "lmstudio:${LMSTUDIO_URL:-http://localhost:1234/v1}" \
    "vllm:${VLLM_URL:-http://localhost:8000/v1}" \
    "llamacpp:${LLAMACPP_URL:-http://localhost:8080/v1}" \
    "localai:${LOCALAI_URL:-http://localhost:8080/v1}"
  do
    name="${pair%%:*}"; url="${pair#*:}"
    if probe_local "$url"; then echo "$name"; return 0; fi
  done
  return 1
}

# ============================================================================
#  UI PRIMITIVES
# ============================================================================
term_width() {
  local w="${COLUMNS:-}"
  [[ -z "$w" ]] && w="$(tput cols 2>/dev/null || echo 80)"
  (( w > 96 )) && w=96; (( w < 50 )) && w=50
  echo "$w"
}

rule() {
  local w; w="$(term_width)"
  local line="" i
  for (( i = 0; i < w - 4; i++ )); do line+="─"; done
  printf '  %s%s%s%s\n' "$DM" "$V2" "$line" "$RS"
}

section() { printf '\n  %s%s▍%s %s%s%s\n' "$BD" "$V1" "$RS" "$BD" "$*" "$RS"; }
ok()      { printf '  %s✔%s %s\n' "$OK" "$RS" "$*"; }
warn()    { printf '  %s!%s %s\n' "$GD" "$RS" "$*"; }
err()     { printf '  %s✘%s %s\n' "$ER" "$RS" "$*" >&2; }
info()    { printf '  %s·%s %s%s%s\n' "$MT" "$RS" "$MT" "$*" "$RS"; }

spin() {
  local msg="$1"; shift
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 rc=0 pid
  mkdir -p "$APP_DIR"
  if [[ ! -t 1 ]]; then
    if "$@" >>"$LOG_FILE" 2>&1; then ok "$msg"; return 0; fi
    err "$msg failed (log: $LOG_FILE)"; return 1
  fi
  "$@" >>"$LOG_FILE" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s%s%s %s%s\033[K' "$PK" "${frames[i % 10]}" "$RS" "$msg" ""
    i=$(( i + 1 )); sleep 0.08
  done
  wait "$pid" || rc=$?
  if (( rc == 0 )); then
    printf '\r  %s✔%s %s\033[K\n' "$OK" "$RS" "$msg"
  else
    printf '\r  %s✘%s %s\033[K\n' "$ER" "$RS" "$msg"
    info "log: $LOG_FILE"
  fi
  return "$rc"
}

print_logo() {
  local lines=(
'     ░███               ░██                              ░██    ░██            ░███                                        ░██    '
'  ░██░██              ░██                               ░██  ░██            ░██░██                                       ░██    '
' ░██  ░██  ░██    ░██ ░████████   ░██████   ░████████    ░██░██            ░██  ░██   ░████████  ░███████  ░████████  ░████████ '
'░█████████ ░██    ░██ ░██    ░██       ░██  ░██    ░██    ░███    ░██████ ░█████████ ░██    ░██ ░██    ░██ ░██    ░██    ░██    '
'░██    ░██ ░██    ░██ ░██    ░██  ░███████  ░██    ░██   ░██░██           ░██    ░██ ░██    ░██ ░█████████ ░██    ░██    ░██    '
'░██    ░██ ░██   ░███ ░██    ░██ ░██   ░██  ░██    ░██  ░██  ░██          ░██    ░██ ░██   ░███ ░██        ░██    ░██    ░██    '
'░██    ░██  ░█████░██ ░██    ░██  ░█████░██ ░██    ░██ ░██    ░██         ░██    ░██  ░█████░██  ░███████  ░██    ░██     ░████ '
'                  ░██                                                                       ░██                                 '
'            ░███████                                                                  ░░███████                                '
  )
  local ramp=(30 36 37 43 44 80 87)
  local max=0 l
  for l in "${lines[@]}"; do (( ${#l} > max )) && max=${#l}; done
  echo
  for l in "${lines[@]}"; do
    local out="" j c n=${#l}
    if [[ -z "$E" ]]; then printf '%s\n' "$l"; continue; fi
    for (( j = 0; j < n; j++ )); do
      c=${ramp[$(( j * ${#ramp[@]} / max ))]}
      out+="${E}[1;38;5;${c}m${l:j:1}"
    done
    printf '%s%s\n' "$out" "$RS"
  done
  echo
}

print_tagline() {
  local provider="${AYHANX_PROVIDER:-deepseek}"
  printf '  %s◆%s %s%sAyhanX-Agent%s  %s· %s · v%s%s\n' \
    "$V1" "$RS" "$BD" "$V1" "$RS" "$MT" "$(provider_label "$provider")" "$VERSION" "$RS"
  rule
}

print_outro() {
  echo; rule
  printf '  %s◆%s %sthanks for using AyhanX-Agent%s\n' "$V1" "$RS" "$BD" "$RS"
  printf '  %s%s%s\n\n' "$MT" "$REPO_URL" "$RS"
}

# ============================================================================
#  ENVIRONMENT
# ============================================================================
find_python() {
  for c in python3.12 python3.11 python3.10 python3.13; do
    if command -v "$c" >/dev/null 2>&1 \
       && "$c" -c 'import sys; sys.exit(0 if (3,10)<=sys.version_info[:2]<=(3,13) else 1)' 2>/dev/null; then
      echo "$c"; return 0
    fi
  done
  if command -v uv >/dev/null 2>&1; then
    local p; p="$(uv python find 3.12 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p" ]]; then echo "$p"; return 0; fi
  fi
  return 1
}

pick_pypi_mirror() {
  local mirrors=(
    "https://pypi.org/simple"
    "https://mirror-pypi.runflare.com/simple"
    "https://mirrors.aliyun.com/pypi/simple"
    "https://pypi.tuna.tsinghua.edu.cn/simple"
  )
  for m in "${mirrors[@]}"; do
    if timeout 6 curl -sSI -o /dev/null "$m/" 2>/dev/null; then echo "$m"; return 0; fi
  done
  return 1
}

ensure_env() {
  section "Environment"
  mkdir -p "$APP_DIR" "$RUNNER_DIR" "$CHATS_DIR"

  local PY
  if ! PY="$(find_python)"; then
    warn "no Python 3.10–3.13 found — installing uv"
    spin "installing uv" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || true
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    if command -v uv >/dev/null 2>&1; then
      spin "fetching Python 3.12" uv python install 3.12 || true
      PY="$(uv python find 3.12 2>/dev/null || true)"
    fi
    [[ -z "${PY:-}" ]] && { err "cannot obtain Python 3.10–3.13"; exit 1; }
  fi
  ok "python → $PY"

  local rebuild=0
  [[ -d "$VENV" ]] || rebuild=1
  [[ -x "$VENV/bin/python" ]] || rebuild=1
  if (( !rebuild )); then
    "$VENV/bin/python" -c 'import httpx,rich,prompt_toolkit,fastapi,uvicorn' 2>/dev/null || rebuild=1
  fi

  if (( rebuild )); then
    local mirror host
    if ! mirror="$(pick_pypi_mirror)"; then
      err "no PyPI mirror reachable — check DNS or internet"
      info "try: echo 'nameserver 1.1.1.1' > /etc/resolv.conf"; exit 1
    fi
    host="$(echo "$mirror" | awk -F/ '{print $3}')"
    ok "package index → $host"
    rm -rf "$VENV"
    spin "creating virtual environment" "$PY" -m venv "$VENV" || { err "venv failed"; exit 1; }
    spin "upgrading pip" "$VENV/bin/pip" install -q --upgrade pip --timeout 10 --retries 1 || true
    spin "installing packages" \
      "$VENV/bin/pip" install --index-url "$mirror" --trusted-host "$host" \
      --timeout 20 --retries 3 httpx rich prompt_toolkit fastapi uvicorn || { err "install failed"; exit 1; }
  else
    ok "runtime ready"
  fi
}

ensure_key() {
  section "Credentials"
  [[ -f "$ENV_FILE" ]] && { set -o allexport; . "$ENV_FILE"; set +o allexport; }

  local provider=""
  if [[ -n "${AYHANX_PROVIDER:-}" && "${AYHANX_PROVIDER}" != "auto" ]]; then
    provider="$AYHANX_PROVIDER"
  elif [[ -n "${DEEPSEEK_BASE_URL:-}" ]]; then
    case "$DEEPSEEK_BASE_URL" in
      *openrouter*) provider="openrouter" ;;
      *groq*)       provider="groq" ;;
      *generativelanguage*) provider="google" ;;
      *:11434*)     provider="ollama" ;;
      *:1234*)      provider="lmstudio" ;;
      *:8000*)      provider="vllm" ;;
      *:8080*)      provider="llamacpp" ;;
      *deepseek*)   provider="deepseek" ;;
    esac
  fi

  if [[ -z "$provider" || "${AYHANX_PROVIDER:-}" == "auto" ]]; then
    local detected=""
    if detected="$(detect_local)"; then
      provider="$detected"
      ok "detected local server → $(provider_label "$provider")"
    fi
  fi

  if [[ -z "$provider" ]]; then provider="$(provider_of_key "${DEEPSEEK_API_KEY:-}")"; fi
  if [[ -z "$provider" && -f "$PROVIDER_FILE" ]]; then
    provider="$(cat "$PROVIDER_FILE" 2>/dev/null || echo "")"
  fi
  if [[ -z "$provider" ]]; then provider="deepseek"; fi

  if is_local_provider "$provider"; then
    DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-local}"
    ok "local provider — no API key required"
  else
    if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
      warn "no API key found for $(provider_label "$provider")"
      printf '  %s›%s paste your key: ' "$PK" "$RS"
      read -r -s DEEPSEEK_API_KEY || true
      echo
      [[ -z "${DEEPSEEK_API_KEY:-}" ]] && { err "required"; exit 1; }
      printf 'DEEPSEEK_API_KEY=%s\n' "$DEEPSEEK_API_KEY" > "$ENV_FILE"
      chmod 600 "$ENV_FILE"
      ok "key saved"
    else
      ok "key loaded"
    fi
  fi

  printf '%s\n' "$provider" > "$PROVIDER_FILE"
  export AYHANX_PROVIDER="$provider"
  export DEEPSEEK_API_KEY
  export DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-$(provider_url "$provider")}"
  export DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-$(provider_default_model "$provider")}"

  if [[ ! -f "$PROVIDERS_FILE" ]]; then
    "$VENV/bin/python" - "$PROVIDERS_FILE" "$provider" \
      "$DEEPSEEK_API_KEY" "$DEEPSEEK_BASE_URL" "$DEEPSEEK_MODEL" <<'PYSEED'
import json, sys, os
path, name, key, url, model = sys.argv[1:6]
json.dump({name: {"key": key, "url": url, "model": model}}, open(path, "w"), indent=2)
os.chmod(path, 0o600)
PYSEED
  fi

  ok "provider → $(provider_label "$provider")"
  info "endpoint → $DEEPSEEK_BASE_URL"
  info "model    → $DEEPSEEK_MODEL"
}

# ============================================================================
#  WRITE: runner/tools.py  (FULL POWER — agent can code & run shell)
# ============================================================================
write_tools() {
  mkdir -p "$RUNNER_DIR"
  cat > "$RUNNER_DIR/tools.py" <<'PYEOF'
"""AyhanX-Agent — full-power tools (filesystem + shell + python)."""
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

TOOL_SPECS = [
    {"type": "function", "function": {
        "name": "get_current_time",
        "description": "Get the current UTC date and time in ISO 8601 format.",
        "parameters": {"type": "object", "properties": {}},
    }},
    {"type": "function", "function": {
        "name": "calculate",
        "description": "Evaluate a simple arithmetic expression.",
        "parameters": {"type": "object", "properties": {
            "expression": {"type": "string", "description": "e.g. '2 + 3 * 4'"}},
            "required": ["expression"]},
    }},
    {"type": "function", "function": {
        "name": "list_directory",
        "description": "List files in a directory under the user's home.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "relative path (default: home)"}}},
    }},
    {"type": "function", "function": {
        "name": "read_file",
        "description": "Read the full content of a text file under the user's home.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}}, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "write_file",
        "description": (
            "Create or overwrite a text file with the given content. "
            "Creates parent directories automatically. "
            "Use this to actually write code, not just show it."
        ),
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "relative path e.g. 'projects/app.py'"},
            "content": {"type": "string", "description": "full file content"}},
            "required": ["path", "content"]},
    }},
    {"type": "function", "function": {
        "name": "edit_file",
        "description": (
            "Replace an exact string in a file. Use for small edits. "
            "old_string must be unique in the file."
        ),
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "old_string": {"type": "string", "description": "exact text to replace"},
            "new_string": {"type": "string", "description": "replacement text"}},
            "required": ["path", "old_string", "new_string"]},
    }},
    {"type": "function", "function": {
        "name": "make_dir",
        "description": "Create a directory (and parents) under the user's home.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}}, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "delete_file",
        "description": "Delete a file (not a directory) under the user's home.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}}, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "run_shell",
        "description": (
            "Run a shell command in the user's home directory. "
            "Use for: running scripts, installing packages, git, tests, etc. "
            "Returns stdout + stderr + exit code. "
            "NEVER use destructive commands (rm -rf /, mkfs, dd if=/dev/zero)."
        ),
        "parameters": {"type": "object", "properties": {
            "command": {"type": "string", "description": "shell command"},
            "timeout": {"type": "integer", "description": "seconds (default 30)"}},
            "required": ["command"]},
    }},
    {"type": "function", "function": {
        "name": "run_python",
        "description": (
            "Write Python code to a temp file, run with python3, "
            "return the output. Use for quick experiments without saving."
        ),
        "parameters": {"type": "object", "properties": {
            "code": {"type": "string", "description": "python source code"}},
            "required": ["code"]},
    }},
]


def _safe_resolve(p):
    base = Path.home()
    if not p:
        return base
    t = (base / p).expanduser().resolve()
    if t != base and base not in t.parents:
        raise ValueError(f"path escapes home directory: {p}")
    return t


def _err(m): return json.dumps({"error": m})
def _ok(m, **extra): return json.dumps({"ok": True, "message": m, **extra})


BLOCKED_PATTERNS = (
    "rm -rf /", "rm -rf /*", "mkfs", ":(){", "dd if=/dev/zero",
    "> /dev/sda", "chmod -R 000 /", ":(){:|:&};:",
)

def _is_destructive(cmd):
    c = cmd.lower()
    return any(p in c for p in BLOCKED_PATTERNS)


def tool_get_current_time(_a):
    return datetime.now(timezone.utc).isoformat()


def tool_calculate(a):
    e = a.get("expression", "").strip()
    if not e: return _err("empty expression")
    if any(ch not in "0123456789+-*/(). " for ch in e):
        return _err(f"disallowed character in {e!r}")
    try: return str(eval(e, {"__builtins__": {}}, {}))
    except Exception as ex: return _err(f"evaluation failed: {ex}")


def tool_list_directory(a):
    rel = a.get("path", "").strip()
    try: t = _safe_resolve(rel)
    except ValueError as e: return _err(str(e))
    if not t.exists(): return _err(f"path not found: {t}")
    if not t.is_dir(): return _err(f"not a directory: {t}")
    try: items = sorted(t.iterdir())
    except PermissionError: return _err("permission denied")
    result = []
    for p in items[:300]:
        try:
            st = p.stat()
            result.append({"name": p.name,
                            "type": "dir" if p.is_dir() else "file",
                            "size": st.st_size if p.is_file() else None,
                            "modified": datetime.fromtimestamp(st.st_mtime).isoformat()})
        except Exception:
            result.append({"name": p.name, "type": "unknown"})
    return json.dumps(result, indent=2)


def tool_read_file(a):
    rel = a.get("path", "").strip()
    if not rel: return _err("path required")
    try: t = _safe_resolve(rel)
    except ValueError as e: return _err(str(e))
    if not t.exists(): return _err(f"file not found: {t}")
    if not t.is_file(): return _err(f"not a file: {t}")
    try: data = t.read_text(encoding="utf-8", errors="replace")
    except PermissionError: return _err("permission denied")
    if len(data) > 200 * 1024:
        data = data[:200 * 1024] + "\n\n... [truncated at 200 KB]"
    return data


def tool_write_file(a):
    rel = a.get("path", "").strip()
    content = a.get("content", "")
    if not rel: return _err("path required")
    try: t = _safe_resolve(rel)
    except ValueError as e: return _err(str(e))
    if t.exists() and t.is_dir(): return _err(f"target is a directory: {t}")
    try:
        t.parent.mkdir(parents=True, exist_ok=True)
        t.write_text(content, encoding="utf-8")
        return _ok(f"wrote {t.stat().st_size} bytes to {t}",
                    path=str(t), size=t.stat().st_size)
    except PermissionError: return _err(f"permission denied: {t}")
    except Exception as e: return _err(f"{type(e).__name__}: {e}")


def tool_edit_file(a):
    rel = a.get("path", "").strip()
    old = a.get("old_string", "")
    new = a.get("new_string", "")
    if not rel: return _err("path required")
    if not old: return _err("old_string required")
    try: t = _safe_resolve(rel)
    except ValueError as e: return _err(str(e))
    if not t.exists(): return _err(f"file not found: {t}")
    if not t.is_file(): return _err(f"not a file: {t}")
    try: content = t.read_text(encoding="utf-8")
    except PermissionError: return _err("permission denied")
    count = content.count(old)
    if count == 0: return _err(f"old_string not found in {t}")
    if count > 1: return _err(f"old_string appears {count} times — must be unique")
    try:
        t.write_text(content.replace(old, new, 1), encoding="utf-8")
        return _ok(f"edited {t}", path=str(t))
    except PermissionError: return _err("permission denied")


def tool_make_dir(a):
    rel = a.get("path", "").strip()
    if not rel: return _err("path required")
    try: t = _safe_resolve(rel)
    except ValueError as e: return _err(str(e))
    try:
        t.mkdir(parents=True, exist_ok=True)
        return _ok(f"created {t}", path=str(t))
    except PermissionError: return _err("permission denied")
    except Exception as e: return _err(f"{type(e).__name__}: {e}")


def tool_delete_file(a):
    rel = a.get("path", "").strip()
    if not rel: return _err("path required")
    try: t = _safe_resolve(rel)
    except ValueError as e: return _err(str(e))
    if not t.exists(): return _err(f"file not found: {t}")
    if t.is_dir(): return _err(f"target is a directory (not deleting): {t}")
    try:
        t.unlink()
        return _ok(f"deleted {t}", path=str(t))
    except PermissionError: return _err("permission denied")


def tool_run_shell(a):
    cmd = a.get("command", "").strip()
    if not cmd: return _err("command required")
    if _is_destructive(cmd): return _err("refused: destructive command detected")
    try: timeout = max(1, min(int(a.get("timeout", 30)), 300))
    except (ValueError, TypeError): timeout = 30
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                            timeout=timeout, cwd=str(Path.home()))
        out = r.stdout
        err = r.stderr
        combined = ""
        if out: combined += out
        if err:
            if combined: combined += "\n"
            combined += f"[stderr]\n{err}"
        if r.returncode != 0: combined += f"\n[exit code: {r.returncode}]"
        return combined[:10000] or "(no output)"
    except subprocess.TimeoutExpired: return _err(f"timed out after {timeout}s")
    except FileNotFoundError as e: return _err(f"command not found: {e}")
    except Exception as e: return _err(f"{type(e).__name__}: {e}")


def tool_run_python(a):
    code = a.get("code", "")
    if not code: return _err("code required")
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False,
                                          prefix="ai_agent_", encoding="utf-8") as f:
            f.write(code); tmp = f.name
        try:
            r = subprocess.run(["python3", tmp], capture_output=True, text=True,
                                timeout=60, cwd=str(Path.home()))
            out = r.stdout
            err = r.stderr
            combined = ""
            if out: combined += out
            if err:
                if combined: combined += "\n"
                combined += f"[stderr]\n{err}"
            if r.returncode != 0: combined += f"\n[exit code: {r.returncode}]"
            return combined[:10000] or "(no output)"
        finally:
            try: os.unlink(tmp)
            except Exception: pass
    except subprocess.TimeoutExpired: return _err("python timed out (60s)")
    except Exception as e: return _err(f"{type(e).__name__}: {e}")


TOOL_IMPLS = {
    "get_current_time": tool_get_current_time,
    "calculate": tool_calculate,
    "list_directory": tool_list_directory,
    "read_file": tool_read_file,
    "write_file": tool_write_file,
    "edit_file": tool_edit_file,
    "make_dir": tool_make_dir,
    "delete_file": tool_delete_file,
    "run_shell": tool_run_shell,
    "run_python": tool_run_python,
}
PYEOF
}

# ============================================================================
#  WRITE: runner/tui.py  (terminal chat)
# ============================================================================
write_tui() {
  cat > "$RUNNER_DIR/tui.py" <<'PYEOF'
"""AyhanX-Agent — terminal chat."""
import html, json, os, sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
import httpx
from prompt_toolkit import PromptSession
from prompt_toolkit.completion import WordCompleter
from prompt_toolkit.formatted_text import HTML
from prompt_toolkit.history import FileHistory
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.styles import Style
from rich import box
from rich.console import Console, Group
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.spinner import Spinner
from rich.table import Table
from rich.text import Text
from .tools import TOOL_IMPLS, TOOL_SPECS

VERSION = os.environ.get("AI_RUNNER_VERSION", "4.0.0")
APP_DIR = Path(os.environ.get("APP_DIR", Path.home() / ".ai_platform"))
CONFIG_PATH = APP_DIR / "config.json"
HISTORY_PATH = APP_DIR / "history.txt"
CHATS_DIR = APP_DIR / "chats"
PROVIDERS_FILE = APP_DIR / "providers.json"
CHATS_DIR.mkdir(parents=True, exist_ok=True)

PROVIDER = os.environ.get("AYHANX_PROVIDER", "deepseek")
LOCAL_PROVIDERS = {"ollama", "lmstudio", "vllm", "llamacpp", "localai"}

PROVIDER_DEFAULTS = {
    "deepseek":   {"url": "https://api.deepseek.com", "model": "deepseek-chat"},
    "openrouter": {"url": "https://openrouter.ai/api/v1", "model": "deepseek/deepseek-chat"},
    "groq":       {"url": "https://api.groq.com/openai/v1", "model": "llama-3.3-70b-versatile"},
    "google":     {"url": "https://generativelanguage.googleapis.com/v1beta/openai", "model": "gemini-2.5-flash"},
    "ollama":     {"url": "http://localhost:11434/v1", "model": "qwen2.5:3b"},
    "lmstudio":   {"url": "http://localhost:1234/v1", "model": "local-model"},
    "vllm":       {"url": "http://localhost:8000/v1", "model": "local-model"},
    "llamacpp":   {"url": "http://localhost:8080/v1", "model": "local-model"},
    "localai":    {"url": "http://localhost:8080/v1", "model": "local-model"},
}

PROVIDER_MODELS = {
    "deepseek": ["deepseek-chat", "deepseek-reasoner"],
    "openrouter": ["deepseek/deepseek-chat", "deepseek/deepseek-chat-v3-0324:free",
                   "deepseek/deepseek-r1:free", "meta-llama/llama-3.3-70b-instruct:free",
                   "qwen/qwen-2.5-72b-instruct:free", "microsoft/phi-4:free"],
    "groq": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768", "gemma2-9b-it"],
    "google": ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-flash-latest", "gemini-flash-lite-latest"],
    "ollama": [], "lmstudio": [], "vllm": [], "llamacpp": [], "localai": [],
}

LABELS = {"deepseek": "DeepSeek", "openrouter": "OpenRouter", "groq": "Groq",
          "google": "Google AI Studio", "ollama": "Ollama", "lmstudio": "LM Studio",
          "vllm": "vLLM", "llamacpp": "llama.cpp", "localai": "LocalAI"}

def provider_label(name=None): return LABELS.get(name or PROVIDER, (name or PROVIDER))
def is_local(name=None): return (name or PROVIDER) in LOCAL_PROVIDERS

def load_providers():
    if PROVIDERS_FILE.exists():
        try: return json.loads(PROVIDERS_FILE.read_text())
        except Exception: pass
    name = PROVIDER
    d = PROVIDER_DEFAULTS.get(name, PROVIDER_DEFAULTS["deepseek"])
    return {name: {"key": os.environ.get("DEEPSEEK_API_KEY", "local" if is_local(name) else ""),
                    "url": os.environ.get("DEEPSEEK_BASE_URL", d["url"]),
                    "model": os.environ.get("DEEPSEEK_MODEL", d["model"])}}

def save_providers(data):
    PROVIDERS_FILE.write_text(json.dumps(data, indent=2))
    try: os.chmod(PROVIDERS_FILE, 0o600)
    except Exception: pass

def switch_provider(name, providers, cfg):
    global PROVIDER, IS_LOCAL, MODELS, PROVIDER_LABEL
    if name not in providers: return False
    p = providers[name]
    os.environ["DEEPSEEK_API_KEY"] = p["key"]
    os.environ["DEEPSEEK_BASE_URL"] = p["url"]
    os.environ["DEEPSEEK_MODEL"] = p["model"]
    os.environ["AYHANX_PROVIDER"] = name
    try: (APP_DIR / "provider").write_text(name)
    except Exception: pass
    PROVIDER = name
    PROVIDER_LABEL = provider_label(name)
    IS_LOCAL = is_local(name)
    MODELS = PROVIDER_MODELS.get(name, [])
    cfg.model = p["model"]; cfg.save()
    return True

PROVIDER_LABEL = provider_label()
IS_LOCAL = is_local()
MODELS = PROVIDER_MODELS.get(PROVIDER, PROVIDER_MODELS["deepseek"])
START = os.environ.get("AYHANX_START", "new")

def all_models(cfg): return MODELS + [m for m in cfg.custom_models if m not in MODELS]
def save_last(conv):
    if conv.messages: (CHATS_DIR / "last.json").write_text(json.dumps(conv.messages, indent=2))

def fetch_server_models(base_url, api_key):
    h = {"Authorization": f"Bearer {api_key}"}
    if PROVIDER == "openrouter":
        h["HTTP-Referer"] = "https://github.com/AyhanMansur/AyhanX-Agent"
        h["X-Title"] = "AyhanX-Agent"
    try:
        r = httpx.get(f"{base_url.rstrip('/')}/models", headers=h, timeout=6)
        if r.status_code == 200: return [m["id"] for m in r.json().get("data", [])]
    except Exception: pass
    return []

def refresh_local_models(cfg):
    if not IS_LOCAL: return []
    base = os.environ.get("DEEPSEEK_BASE_URL", "")
    key = os.environ.get("DEEPSEEK_API_KEY", "local")
    ids = fetch_server_models(base, key)
    if ids:
        for m in ids:
            if m not in cfg.custom_models and m not in MODELS: cfg.custom_models.append(m)
        cfg.save()
        if cfg.model not in ids: cfg.model = ids[0]; cfg.save()
    return ids

VIOLET = "#40e0d0"; VIOLET_DEEP = "#0f9d9a"; CYAN = "#5eead4"
GOLD = "#fbbf24"; MINT = "#34d399"; RED = "#f87171"
MUTED = "#64748b"; SOFT = "#94a3b8"; TEXT = "#e2e8f0"
console = Console(highlight=False)

@dataclass
class Config:
    model: str = "deepseek-chat"
    system_prompt: str = ""
    agent_mode: bool = False
    max_context_messages: int = 40
    custom_models: list = field(default_factory=list)
    @classmethod
    def load(cls):
        if CONFIG_PATH.exists():
            try:
                d = json.loads(CONFIG_PATH.read_text())
                return cls(**{k: v for k, v in d.items() if k in cls.__annotations__})
            except Exception: pass
        return cls()
    def save(self):
        CONFIG_PATH.write_text(json.dumps(self.__dict__, indent=2))
        try: os.chmod(CONFIG_PATH, 0o600)
        except Exception: pass

@dataclass
class Conversation:
    messages: list = field(default_factory=list)
    created: str = field(default_factory=lambda: datetime.now().isoformat())
    def add_user(self, t): self.messages.append({"role": "user", "content": t})
    def add_assistant(self, t): self.messages.append({"role": "assistant", "content": t})
    def trim(self, n):
        s = [m for m in self.messages if m["role"] == "system"]
        d = [m for m in self.messages if m["role"] != "system"]
        if len(d) > n: d = d[-n:]
        self.messages = s + d
    def save(self, name):
        p = CHATS_DIR / f"{name}.json"; p.write_text(json.dumps(self.messages, indent=2)); return p
    @classmethod
    def load(cls, name):
        p = CHATS_DIR / f"{name}.json"
        if not p.exists(): raise FileNotFoundError(f"no chat named '{name}'")
        c = cls(); c.messages = json.loads(p.read_text()); return c
    def to_api(self): return [m for m in self.messages if m.get("content", "").strip()]

class DeepSeekClient:
    def __init__(self, key, base, model, provider="deepseek"):
        self.api_key = key; self.base_url = base.rstrip("/")
        self.model = model; self.provider = provider
    def _headers(self):
        h = {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"}
        if self.provider == "openrouter":
            h["HTTP-Referer"] = "https://github.com/AyhanMansur/AyhanX-Agent"
            h["X-Title"] = "AyhanX-Agent"
        return h
    def _hint(self, s):
        b = {401: "invalid key", 402: "no balance", 404: "model not found — try /model",
             429: "rate limited"}.get(s, "")
        if not b: return ""
        if self.provider == "openrouter": return b + " — openrouter.ai/keys"
        if self.provider == "google": return b + " — aistudio.google.com/apikey"
        if self.provider in LOCAL_PROVIDERS: return b + " — is the server running?"
        return b + " — platform.deepseek.com/api_keys"
    def _error(self, s, body):
        msg = body
        try: msg = json.loads(body).get("error", {}).get("message", body)
        except Exception: pass
        h = self._hint(s)
        return f"HTTP {s}: {msg}" + (f"\n→ {h}" if h else "")
    def chat(self, messages, tools=None, stream=True):
        p = {"model": self.model, "messages": messages, "stream": stream}
        if tools: p["tools"] = tools; p["tool_choice"] = "auto"
        c = httpx.Client(timeout=180)
        return self._stream(c, p) if stream else self._nonstream(c, p)
    def _stream(self, client, payload):
        def gen():
            try:
                with client.stream("POST", f"{self.base_url}/chat/completions",
                                   headers=self._headers(), json=payload) as r:
                    if r.status_code >= 400:
                        yield {"error": self._error(r.status_code, r.read().decode(errors="replace"))}; return
                    for line in r.iter_lines():
                        if not line.startswith("data:"): continue
                        d = line[5:].strip()
                        if d == "[DONE]": break
                        try: o = json.loads(d)
                        except json.JSONDecodeError: continue
                        delta = o.get("choices", [{}])[0].get("delta", {})
                        if c := delta.get("content"): yield {"text": c}
            finally: client.close()
        return gen()
    def _nonstream(self, client, payload):
        try:
            r = client.post(f"{self.base_url}/chat/completions", headers=self._headers(), json=payload)
            if r.status_code >= 400: return {"error": self._error(r.status_code, r.text)}
            return r.json()
        finally: client.close()

def _rgb(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5))

def gradient(text, s=VIOLET_DEEP, e=CYAN):
    a, b = _rgb(s), _rgb(e); out = Text(); n = max(len(text)-1, 1)
    for i, ch in enumerate(text):
        k = i/n; c = "#" + "".join(f"{round(a[j]+(b[j]-a[j])*k):02x}" for j in range(3))
        out.append(ch, style=f"bold {c}")
    return out

def model_chip(n): return Text(f" {n} ", style=f"bold #0f0a1f on {VIOLET}")
def mode_chip(a): return Text(" AGENT ", style=f"bold #1c1600 on {GOLD}") if a else Text(" CHAT ", style=f"bold #04221a on {MINT}")
def provider_chip():
    l = f" {PROVIDER_LABEL} "
    return Text(l, style="bold #1c1600 on #fbbf24") if IS_LOCAL else Text(l, style=f"bold #0a0f1c on {CYAN}")

def show_header(cfg):
    left = Text.assemble(("◆ ", VIOLET), gradient("AyhanX-Agent"), ("   ", ""), (f"v{VERSION}", MUTED))
    right = Text.assemble(provider_chip(), ("  ", ""), model_chip(cfg.model), ("  ", ""), mode_chip(cfg.agent_mode))
    g = Table.grid(expand=True); g.add_column(ratio=1); g.add_column(justify="right"); g.add_row(left, right)
    console.print(Panel(g, box=box.ROUNDED, border_style=VIOLET_DEEP, padding=(0, 2)))
    console.print(Text("  type a message · /help · /provider · Ctrl+D exit", style=MUTED))
    console.print()

def notice(m, c=MINT): console.print(Text(f"  {m}", style=c))
def error_panel(m): return Panel(Text(m, style=RED), title=Text("error", style=f"bold {RED}"),
                                   title_align="left", box=box.ROUNDED, border_style=RED, padding=(0, 2))
def assistant_panel(t, thinking=False):
    title = Text.assemble(("◆ ", VIOLET), (PROVIDER_LABEL, f"bold {VIOLET}"),
                          ("  thinking…" if thinking else "", MUTED))
    return Panel(Markdown(t or ""), title=title, title_align="left", box=box.ROUNDED,
                 border_style=VIOLET_DEEP, padding=(0, 2))
def print_user(t):
    console.print()
    console.print(Text.assemble((" you ", f"bold #0f0a1f on {CYAN}"), ("  ", ""), (t, TEXT)))
    console.print()
def tool_card(n, a, r):
    ag = json.dumps(a, ensure_ascii=False)[:90]; pv = r[:140].replace("\n", " ")
    if len(r) > 140: pv += "…"
    console.print(Text.assemble(("  ⚙ ", GOLD), (n, f"bold {GOLD}"), ("  ", ""), (ag, MUTED)))
    console.print(Text.assemble(("    └ ", "#334155"), (pv, SOFT)))

def help_panel():
    rows = [("/new","new"),("/clear","clear"),("/model [name]","models"),
            ("/model refresh","refresh local"),("/model add <n>","add model"),
            ("/provider [name]","list/switch provider"),("/provider add <n>","add provider"),
            ("/provider remove <n>","remove provider"),("/system [text]","set system prompt"),
            ("/agent","toggle agent (full terminal access)"),
            ("/save [n]","save"),("/load <n>","load"),("/chats","list saved"),
            ("/history","print"),("/info","config"),("/exit","quit")]
    t = Table.grid(padding=(0, 3)); t.add_column(style=f"bold {CYAN}", no_wrap=True); t.add_column(style=SOFT)
    for c, d in rows: t.add_row(c, d)
    keys = Text.assemble(("Enter", f"bold {TEXT}"),(" send   ", MUTED),
                         ("Esc+Enter", f"bold {TEXT}"),(" newline   ", MUTED),
                         ("↑ ↓", f"bold {TEXT}"),(" history   ", MUTED),
                         ("Ctrl+C", f"bold {TEXT}"),(" cancel", MUTED))
    console.print(Panel(Group(t, Text(""), keys), title=Text("commands", style=f"bold {VIOLET}"),
                        title_align="left", box=box.ROUNDED, border_style=VIOLET_DEEP, padding=(1, 2)))

def info_panel(cfg, conv):
    t = Table.grid(padding=(0, 3)); t.add_column(style=f"bold {VIOLET}", no_wrap=True); t.add_column(style=TEXT)
    t.add_row("provider", PROVIDER_LABEL)
    t.add_row("endpoint", os.environ.get("DEEPSEEK_BASE_URL", "?"))
    t.add_row("model", cfg.model)
    t.add_row("mode", "agent" if cfg.agent_mode else "chat")
    t.add_row("system prompt", "set" if cfg.system_prompt else "none")
    t.add_row("messages", str(len(conv.messages)))
    t.add_row("config", str(CONFIG_PATH)); t.add_row("providers", str(PROVIDERS_FILE)); t.add_row("chats", str(CHATS_DIR))
    console.print(Panel(t, title=Text("info", style=f"bold {VIOLET}"), title_align="left",
                        box=box.ROUNDED, border_style=VIOLET_DEEP, padding=(1, 2)))

def chats_table():
    chats = sorted(CHATS_DIR.glob("*.json"))
    if not chats: notice("no saved chats", MUTED); return
    t = Table(box=box.SIMPLE_HEAD, header_style=f"bold {VIOLET}", border_style=MUTED, expand=False)
    t.add_column("name", style=f"bold {CYAN}"); t.add_column("msgs", justify="right"); t.add_column("updated", style=SOFT)
    for p in chats:
        try: n = str(len(json.loads(p.read_text())))
        except Exception: n = "?"
        t.add_row(p.stem, n, datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M"))
    console.print(t)

def print_history(conv):
    if not conv.messages: notice("nothing yet", MUTED); return
    for m in conv.messages:
        if m["role"] == "user": console.print(Text.assemble(("❯ ", f"bold {CYAN}"), (m["content"], TEXT)))
        elif m["role"] == "assistant": console.print(Markdown(m["content"]))
        console.print()

KB = KeyBindings()
@KB.add("enter")
def _(e): e.current_buffer.validate_and_handle()
@KB.add("escape", "enter")
def _(e): e.current_buffer.insert_text("\n")
@KB.add("c-j")
def _(e): e.current_buffer.insert_text("\n")

PROMPT_STYLE = Style.from_dict({"arrow": f"{VIOLET} bold", "bottom-toolbar": "bg:#0b0a14 #94a3b8",
                                 "completion-menu": "bg:#14122a #e2e8f0",
                                 "completion-menu.completion.current": f"bg:{VIOLET_DEEP} #ffffff"})

def toolbar(cfg, conv):
    mode = '<style fg="#fbbf24"><b>AGENT</b></style>' if cfg.agent_mode else '<style fg="#34d399"><b>CHAT</b></style>'
    pf = "#fbbf24" if IS_LOCAL else "#5eead4"
    return HTML(f' <style fg="{pf}"><b>{html.escape(PROVIDER_LABEL)}</b></style>'
                f'  ·  <style fg="#a78bfa"><b>{html.escape(cfg.model)}</b></style>'
                f'  ·  {mode}  ·  {len(conv.messages)} msgs'
                f'    <style fg="#64748b">/help · /provider · Ctrl+D exit</style>')

AGENT_SYSTEM = (
    "You are AyhanX-Agent, a capable coding assistant with FULL access "
    "to the user's filesystem via tools.\n\n"
    "RULES:\n"
    "1. When the user asks you to create/edit/run code or files, USE the "
    "tools (write_file, edit_file, run_shell, run_python). Do NOT just "
    "show code — actually write and run it.\n"
    "2. When the user asks something that needs real data (time, files, "
    "calculations), call the appropriate tool.\n"
    "3. After creating a file, verify it works (run it if applicable).\n"
    "4. Be concise in your final answer — show what you did.\n"
    "5. Paths are relative to $HOME. Use relative paths.\n"
    "6. NEVER use destructive commands (rm -rf /, mkfs, dd, etc.)"
)

def build_msgs(conv, cfg, agent=False):
    m = conv.to_api()
    if agent:
        prefix = cfg.system_prompt or AGENT_SYSTEM
        m = [{"role": "system", "content": prefix}] + m
    elif cfg.system_prompt:
        m = [{"role": "system", "content": cfg.system_prompt}] + m
    return m

def stream_response(client, conv, cfg):
    buf = []
    live = Live(Spinner("dots", text=Text(" thinking", style=MUTED), style=VIOLET),
                console=console, refresh_per_second=12, transient=False)
    live.start()
    try:
        for c in client.chat(build_msgs(conv, cfg, agent=False), stream=True):
            if "error" in c: live.update(error_panel(c["error"])); live.stop(); return ""
            if "text" in c:
                buf.append(c["text"]); live.update(assistant_panel("".join(buf), thinking=True))
    except httpx.RequestError as e: live.update(error_panel(f"network error: {e}")); live.stop(); return ""
    except KeyboardInterrupt:
        live.update(assistant_panel("".join(buf) + "\n\n*cancelled*")); live.stop(); return "".join(buf)
    full = "".join(buf)
    if not full: live.update(Text("  (empty response)", style=MUTED)); live.stop(); return ""
    live.update(assistant_panel(full)); live.stop(); return full

def run_agent(client, conv, cfg):
    msgs = build_msgs(conv, cfg, agent=True)
    for iteration in range(12):
        with console.status(Text(f" thinking (step {iteration+1})", style=MUTED), spinner="dots", spinner_style=VIOLET):
            try: resp = client.chat(msgs, tools=TOOL_SPECS, stream=False)
            except httpx.RequestError as e: resp = {"error": f"network error: {e}"}
        if isinstance(resp, dict) and "error" in resp:
            console.print(error_panel(resp["error"])); return ""
        msg = resp.get("choices", [{}])[0].get("message", {})
        tcalls = msg.get("tool_calls") or []
        if not tcalls:
            content = msg.get("content") or ""
            console.print(assistant_panel(content)); return content
        if msg.get("content"): console.print(Text(msg["content"], style=TEXT))
        msgs.append(msg)
        for tc in tcalls:
            fn = tc.get("function", {}); name = fn.get("name", "?")
            try: a = json.loads(fn.get("arguments") or "{}")
            except json.JSONDecodeError: a = {}
            impl = TOOL_IMPLS.get(name)
            if impl:
                try: r = impl(a)
                except Exception as e: r = f"Error: {type(e).__name__}: {e}"
            else: r = f"Error: unknown tool '{name}'"
            tool_card(name, a, r)
            msgs.append({"role": "tool", "tool_call_id": tc.get("id", ""), "content": r})
    console.print(error_panel("stopped after 12 steps")); return ""

COMMANDS = ["/help","/new","/clear","/model","/provider","/system","/agent","/save","/load","/chats","/history","/info","/exit"]

def main():
    global IS_LOCAL, MODELS, PROVIDER_LABEL
    key = os.environ.get("DEEPSEEK_API_KEY", "local" if IS_LOCAL else "")
    if not key and not IS_LOCAL: console.print(error_panel("DEEPSEEK_API_KEY is not set")); return 1
    base = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
    cfg = Config.load()
    if os.environ.get("DEEPSEEK_MODEL"): cfg.model = os.environ["DEEPSEEK_MODEL"]
    elif cfg.model not in MODELS and cfg.model not in cfg.custom_models:
        cfg.model = MODELS[0] if MODELS else "local-model"
    providers = load_providers()
    if IS_LOCAL:
        with console.status(Text(f" querying {PROVIDER_LABEL}…", style=MUTED), spinner="dots", spinner_style=VIOLET):
            ids = refresh_local_models(cfg)
        if not ids:
            notice(f"could not reach {PROVIDER_LABEL} at {base}", RED)
            notice("is it running? use /model refresh or /provider to switch", MUTED)
        elif cfg.model not in ids: cfg.model = ids[0]; cfg.save()
    conv = Conversation(); show_header(cfg)
    if START == "resume" and (CHATS_DIR / "last.json").exists():
        conv = Conversation.load("last"); notice(f"resumed · {len(conv.messages)} messages"); console.print()
    session = PromptSession(key_bindings=KB, style=PROMPT_STYLE, history=FileHistory(str(HISTORY_PATH)),
                            completer=WordCompleter(COMMANDS, ignore_case=True), complete_while_typing=True,
                            bottom_toolbar=lambda: toolbar(cfg, conv))
    while True:
        try: raw = session.prompt(HTML("<arrow>❯ </arrow>"))
        except KeyboardInterrupt: console.print(Text("  ^C", style=MUTED)); continue
        except EOFError: save_last(conv); console.print(); notice("bye", MUTED); return 0
        text = raw.strip()
        if not text: continue
        if text.startswith("/"):
            parts = text.split(maxsplit=1); cmd = parts[0].lower()
            args = parts[1].split() if len(parts) > 1 else []
            if cmd in ("/exit", "/quit"): save_last(conv); notice("bye", MUTED); return 0
            elif cmd == "/help": help_panel()
            elif cmd == "/clear": console.clear(); show_header(cfg)
            elif cmd == "/provider":
                if not args:
                    chips = Text.assemble(*[(" " + n + " " + ("◆" if n == PROVIDER else " ") + "  ",
                        f"bold #0f0a1f on {VIOLET}" if n == PROVIDER else f"{SOFT}") for n in providers])
                    console.print(Text("  providers  ", style=MUTED), chips)
                elif args[0].lower() == "add":
                    if len(args) < 2: notice("usage: /provider add <name>", RED); continue
                    pname = args[1].lower(); defaults = PROVIDER_DEFAULTS.get(pname, {"url": "", "model": ""})
                    url_in = console.input(f"  url [{defaults['url']}]: ").strip() or defaults["url"]
                    key_in = "local" if pname in LOCAL_PROVIDERS else console.input("  key: ").strip()
                    model_in = console.input(f"  model [{defaults['model']}]: ").strip() or defaults["model"]
                    providers[pname] = {"key": key_in, "url": url_in, "model": model_in}
                    save_providers(providers); notice(f"✔ {pname} added")
                elif args[0].lower() == "remove":
                    if len(args) < 2: notice("usage: /provider remove <name>", RED); continue
                    if args[1] in providers: del providers[args[1]]; save_providers(providers); notice(f"✔ {args[1]} removed")
                    else: notice(f"unknown: {args[1]}", RED)
                elif args[0] in providers:
                    if switch_provider(args[0], providers, cfg):
                        notice(f"→ switched to {PROVIDER_LABEL}")
                        console.print(f"  [dim]model[/]    {cfg.model}")
                        console.print(f"  [dim]endpoint[/] {os.environ['DEEPSEEK_BASE_URL']}")
                        if IS_LOCAL:
                            with console.status(Text(f" querying {PROVIDER_LABEL}…", style=MUTED), spinner="dots", spinner_style=VIOLET):
                                ids = refresh_local_models(cfg)
                            if ids and cfg.model not in ids: cfg.model = ids[0]; cfg.save()
                        console.print(); show_header(cfg)
                    else: notice(f"switch failed: {args[0]}", RED)
                else:
                    notice(f"unknown provider: {args[0]}", RED)
                    console.print("  [dim]available: " + ", ".join(providers) + "[/]")
            elif cmd == "/model":
                if args and args[0].lower() == "refresh":
                    if not IS_LOCAL: notice("refresh only for local", RED); continue
                    with console.status(Text(f" querying {PROVIDER_LABEL}…", style=MUTED), spinner="dots", spinner_style=VIOLET):
                        ids = refresh_local_models(cfg)
                    notice(f"refreshed · {len(ids)} models" if ids else "no models", MINT if ids else RED); continue
                models = all_models(cfg)
                if not args:
                    if not models: notice("no models — try /model refresh", MUTED); continue
                    chips = Text.assemble(*[(" " + m + " " + ("◆" if m == cfg.model else " ") + "  ",
                        f"bold #0f0a1f on {VIOLET}" if m == cfg.model else f"{SOFT}") for m in models])
                    console.print(Text("  models  ", style=MUTED), chips)
                elif args[0].lower() == "add":
                    if len(args) < 2: notice("usage: /model add <name>", RED)
                    else:
                        n = args[1]
                        if n not in models: cfg.custom_models.append(n); cfg.save()
                        notice(f"model added: {n}")
                elif args[0] in models or IS_LOCAL:
                    cfg.model = args[0]; cfg.save(); os.environ["DEEPSEEK_MODEL"] = args[0]; notice(f"model → {args[0]}")
                else: notice(f"unknown model: {args[0]}", RED)
            elif cmd == "/new": conv = Conversation(); notice("new conversation")
            elif cmd == "/system":
                t = " ".join(args).strip()
                if not t:
                    if cfg.system_prompt: console.print(Panel(Text(cfg.system_prompt, style=TEXT),
                        title=Text("system prompt", style=f"bold {VIOLET}"), title_align="left",
                        box=box.ROUNDED, border_style=VIOLET_DEEP, padding=(0, 2)))
                    else: notice("no system prompt set", MUTED)
                else: cfg.system_prompt = t; cfg.save(); notice("system prompt updated")
            elif cmd == "/agent":
                cfg.agent_mode = not cfg.agent_mode; cfg.save()
                notice("agent mode " + ("on — full terminal access" if cfg.agent_mode else "off"),
                       GOLD if cfg.agent_mode else MUTED)
            elif cmd == "/save":
                n = args[0] if args else datetime.now().strftime("chat-%Y%m%d-%H%M%S")
                try: p = conv.save(n); notice(f"saved → {p}")
                except Exception as e: notice(f"save failed: {e}", RED)
            elif cmd == "/load":
                if not args: notice("usage: /load <name>", RED)
                else:
                    try: conv = Conversation.load(args[0]); notice(f"loaded {len(conv.messages)} messages")
                    except FileNotFoundError as e: notice(str(e), RED)
            elif cmd == "/chats": chats_table()
            elif cmd == "/history": print_history(conv)
            elif cmd == "/info": info_panel(cfg, conv)
            else: notice(f"unknown command: {cmd}", RED)
            continue
        print_user(text); conv.add_user(text); conv.trim(cfg.max_context_messages)
        api_key = os.environ.get("DEEPSEEK_API_KEY", "local" if IS_LOCAL else "")
        base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
        client = DeepSeekClient(api_key, base_url, cfg.model, PROVIDER)
        try:
            if cfg.agent_mode: answer = run_agent(client, conv, cfg)
            else: answer = stream_response(client, conv, cfg)
        except KeyboardInterrupt: notice("cancelled", MUTED); conv.messages.pop(); continue
        if answer: conv.add_assistant(answer)
        else: conv.messages.pop()
        console.print()

if __name__ == "__main__":
    sys.exit(main())
PYEOF
  touch "$RUNNER_DIR/__init__.py"
}

# ============================================================================
#  WRITE: runner/server.py  (web UI with full-power agent)
# ============================================================================
write_server() {
  cat > "$RUNNER_DIR/server.py" <<'PYEOF'
"""AyhanX-Agent — premium web UI with full-power agent."""
import json
import os
from datetime import datetime
from pathlib import Path
from typing import AsyncIterator

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel

try:
    from .tools import TOOL_IMPLS, TOOL_SPECS
except ImportError:
    from tools import TOOL_IMPLS, TOOL_SPECS

VERSION = os.environ.get("AI_RUNNER_VERSION", "4.0.0")
APP_DIR = Path(os.environ.get("APP_DIR", Path.home() / ".ai_platform"))
CONFIG_PATH = APP_DIR / "config.json"
PROVIDERS_FILE = APP_DIR / "providers.json"
PROVIDER_FILE = APP_DIR / "provider"
CHATS_DIR = APP_DIR / "chats"
CHATS_DIR.mkdir(parents=True, exist_ok=True)

LOCAL_PROVIDERS = {"ollama", "lmstudio", "vllm", "llamacpp", "localai"}
LABELS = {"deepseek": "DeepSeek", "openrouter": "OpenRouter", "groq": "Groq",
          "google": "Google AI Studio", "ollama": "Ollama", "lmstudio": "LM Studio",
          "vllm": "vLLM", "llamacpp": "llama.cpp", "localai": "LocalAI"}
PROVIDER_MODELS = {
    "deepseek": ["deepseek-chat", "deepseek-reasoner"],
    "openrouter": ["deepseek/deepseek-chat", "deepseek/deepseek-chat-v3-0324:free",
                   "deepseek/deepseek-r1:free", "meta-llama/llama-3.3-70b-instruct:free",
                   "qwen/qwen-2.5-72b-instruct:free", "microsoft/phi-4:free"],
    "groq": ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768", "gemma2-9b-it"],
    "google": ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-flash-latest", "gemini-flash-lite-latest"],
    "ollama": [], "lmstudio": [], "vllm": [], "llamacpp": [], "localai": [],
}

AGENT_SYSTEM = (
    "You are AyhanX-Agent, a capable coding assistant with FULL access "
    "to the user's filesystem via tools.\n\n"
    "RULES:\n"
    "1. When the user asks you to create/edit/run code or files, USE the "
    "tools (write_file, edit_file, run_shell, run_python). Do NOT just "
    "show code — actually write and run it.\n"
    "2. When the user asks something that needs real data (time, files, "
    "calculations), call the appropriate tool.\n"
    "3. After creating a file, verify it works (run it if applicable).\n"
    "4. Be concise in your final answer — show what you did.\n"
    "5. Paths are relative to $HOME. Use relative paths.\n"
    "6. NEVER use destructive commands (rm -rf /, mkfs, dd, etc.)"
)

def _load_providers():
    if PROVIDERS_FILE.exists():
        try: return json.loads(PROVIDERS_FILE.read_text())
        except Exception: pass
    return {}

def _active():
    try: return PROVIDER_FILE.read_text().strip()
    except Exception: return "deepseek"

def _load_cfg():
    if CONFIG_PATH.exists():
        try: return json.loads(CONFIG_PATH.read_text())
        except Exception: pass
    return {"model": "deepseek-chat", "system_prompt": "", "agent_mode": False}

def _save_cfg(cfg):
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
    try: os.chmod(CONFIG_PATH, 0o600)
    except Exception: pass

def _client_info():
    providers = _load_providers()
    name = _active()
    if name not in providers: name = next(iter(providers), "deepseek")
    p = providers.get(name, {"key": "local", "url": "https://api.deepseek.com", "model": "deepseek-chat"})
    return name, p

def _headers(name, key):
    h = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    if name == "openrouter":
        h["HTTP-Referer"] = "https://github.com/AyhanMansur/AyhanX-Agent"
        h["X-Title"] = "AyhanX-Agent"
    return h

def _err_msg(status, body):
    msg = body
    try: msg = json.loads(body).get("error", {}).get("message", body)
    except Exception: pass
    return f"HTTP {status}: {msg}"

class ChatReq(BaseModel):
    conversation_id: str | None = None
    message: str
    agent: bool = False

class SwitchReq(BaseModel):
    provider: str

class ModelReq(BaseModel):
    model: str

class AgentReq(BaseModel):
    enabled: bool

app = FastAPI(title="AyhanX-Agent", version=VERSION)

@app.get("/api/config")
def get_config():
    name, p = _client_info()
    cfg = _load_cfg()
    return {"version": VERSION, "provider": name, "provider_label": LABELS.get(name, name),
            "is_local": name in LOCAL_PROVIDERS, "model": cfg.get("model", p["model"]),
            "agent_mode": cfg.get("agent_mode", False)}

@app.get("/api/providers")
def list_providers():
    providers = _load_providers()
    return [{"name": k, "label": LABELS.get(k, k), "url": v["url"], "model": v["model"],
             "active": k == _active(), "local": k in LOCAL_PROVIDERS} for k, v in providers.items()]

@app.post("/api/switch")
def switch(req: SwitchReq):
    providers = _load_providers()
    if req.provider not in providers: raise HTTPException(404, "provider not found")
    PROVIDER_FILE.write_text(req.provider)
    p = providers[req.provider]
    cfg = _load_cfg(); cfg["model"] = p["model"]; _save_cfg(cfg)
    return {"ok": True, "provider": req.provider, "model": p["model"]}

@app.get("/api/models")
def list_models():
    name, p = _client_info()
    cfg = _load_cfg()
    built_in = PROVIDER_MODELS.get(name, [])
    custom = cfg.get("custom_models", [])
    all_m = built_in + [m for m in custom if m not in built_in]
    if name in LOCAL_PROVIDERS:
        try:
            r = httpx.get(f"{p['url'].rstrip('/')}/models", headers=_headers(name, p["key"]), timeout=4)
            if r.status_code == 200:
                ids = [m["id"] for m in r.json().get("data", [])]
                for m in ids:
                    if m not in all_m: all_m.append(m)
        except Exception: pass
    return {"models": all_m, "current": cfg.get("model", p["model"])}

@app.post("/api/model")
def set_model(req: ModelReq):
    cfg = _load_cfg(); cfg["model"] = req.model; _save_cfg(cfg)
    return {"ok": True, "model": req.model}

@app.post("/api/agent")
def set_agent(req: AgentReq):
    cfg = _load_cfg(); cfg["agent_mode"] = req.enabled; _save_cfg(cfg)
    return {"ok": True, "agent_mode": req.enabled}

@app.get("/api/conversations")
def list_convs():
    items = []
    for p in sorted(CHATS_DIR.glob("*.json"), key=lambda x: x.stat().st_mtime, reverse=True):
        if p.stem == "last": continue
        try: n = len(json.loads(p.read_text()))
        except Exception: n = 0
        items.append({"id": p.stem, "messages": n,
                       "updated": datetime.fromtimestamp(p.stat().st_mtime).isoformat()})
    return items

@app.delete("/api/conversations/{cid}")
def del_conv(cid: str):
    p = CHATS_DIR / f"{cid}.json"
    if p.exists(): p.unlink()
    return {"ok": True}

@app.get("/api/conversations/{cid}")
def get_conv(cid: str):
    p = CHATS_DIR / f"{cid}.json"
    if not p.exists(): raise HTTPException(404, "not found")
    return {"id": cid, "messages": json.loads(p.read_text())}

@app.post("/api/chat")
async def chat(req: ChatReq):
    text = req.message.strip()
    if not text: raise HTTPException(400, "empty message")

    name, p = _client_info()
    cfg = _load_cfg()
    key = p["key"]; base = p["url"].rstrip("/")
    model = cfg.get("model", p["model"])
    system_prompt = cfg.get("system_prompt", "")

    cid = req.conversation_id or datetime.now().strftime("chat-%Y%m%d-%H%M%S")
    conv_path = CHATS_DIR / f"{cid}.json"
    if conv_path.exists():
        try: messages = json.loads(conv_path.read_text())
        except Exception: messages = []
    else:
        messages = []

    messages.append({"role": "user", "content": text})
    conv_path.write_text(json.dumps(messages, indent=2))

    async def stream():
        try:
            yield f"data: {json.dumps({'type':'start','conversation_id':cid})}\n\n"
            if req.agent:
                async for chunk in _run_agent(messages, name, key, base, model, system_prompt, cid, conv_path):
                    yield chunk
            else:
                async for chunk in _run_chat(messages, name, key, base, model, system_prompt, cid, conv_path):
                    yield chunk
        except Exception as e:
            yield f"data: {json.dumps({'type':'error','message':str(e)})}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")

async def _run_chat(messages, name, key, base, model, system_prompt, cid, conv_path):
    msgs = []
    if system_prompt: msgs.append({"role": "system", "content": system_prompt})
    msgs.extend(messages)
    full = []
    async with httpx.AsyncClient(timeout=180) as client:
        async with client.stream("POST", f"{base}/chat/completions",
                                  headers=_headers(name, key),
                                  json={"model": model, "messages": msgs, "stream": True}) as r:
            if r.status_code >= 400:
                body = (await r.aread()).decode(errors="replace")
                yield f"data: {json.dumps({'type':'error','message':_err_msg(r.status_code, body)})}\n\n"
                return
            async for line in r.aiter_lines():
                if not line.startswith("data:"): continue
                data = line[5:].strip()
                if data == "[DONE]": break
                try: obj = json.loads(data)
                except json.JSONDecodeError: continue
                delta = obj.get("choices", [{}])[0].get("delta", {})
                if chunk := delta.get("content"):
                    full.append(chunk)
                    yield f"data: {json.dumps({'type':'delta','text':chunk})}\n\n"
    answer = "".join(full)
    messages.append({"role": "assistant", "content": answer})
    conv_path.write_text(json.dumps(messages, indent=2))
    yield f"data: {json.dumps({'type':'done'})}\n\n"

async def _run_agent(messages, name, key, base, model, system_prompt, cid, conv_path):
    msgs = [{"role": "system", "content": system_prompt or AGENT_SYSTEM}] + messages
    for iteration in range(12):
        print(f"[agent] iter {iteration+1} · {model}", flush=True)
        try:
            async with httpx.AsyncClient(timeout=180) as client:
                r = await client.post(f"{base}/chat/completions", headers=_headers(name, key),
                                       json={"model": model, "messages": msgs,
                                             "tools": TOOL_SPECS, "tool_choice": "auto"})
        except Exception as e:
            yield f"data: {json.dumps({'type':'error','message':f'network: {e}'})}\n\n"
            return
        if r.status_code >= 400:
            yield f"data: {json.dumps({'type':'error','message':_err_msg(r.status_code, r.text)})}\n\n"
            return
        obj = r.json()
        msg = obj.get("choices", [{}])[0].get("message", {})
        tcalls = msg.get("tool_calls") or []
        print(f"[agent] tool_calls: {len(tcalls)}", flush=True)
        if not tcalls:
            content = msg.get("content") or ""
            if content:
                yield f"data: {json.dumps({'type':'delta','text':content})}\n\n"
            messages.append({"role": "assistant", "content": content})
            conv_path.write_text(json.dumps(messages, indent=2))
            yield f"data: {json.dumps({'type':'done'})}\n\n"
            return
        if msg.get("content"):
            yield f"data: {json.dumps({'type':'delta','text':msg['content']})}\n\n"
        msgs.append(msg)
        for tc in tcalls:
            fn = tc.get("function", {}); tname = fn.get("name", "?")
            try: args = json.loads(fn.get("arguments") or "{}")
            except json.JSONDecodeError: args = {}
            print(f"[agent] {tname}({json.dumps(args)[:80]})", flush=True)
            yield f"data: {json.dumps({'type':'tool','name':tname,'args':args})}\n\n"
            impl = TOOL_IMPLS.get(tname)
            if impl:
                try: result = impl(args)
                except Exception as e: result = f"{type(e).__name__}: {e}"
            else: result = f"unknown tool: {tname}"
            print(f"[agent] → {str(result)[:100]}", flush=True)
            yield f"data: {json.dumps({'type':'tool_result','text':result[:800]})}\n\n"
            msgs.append({"role": "tool", "tool_call_id": tc.get("id", ""), "content": result})
    yield f"data: {json.dumps({'type':'delta','text':'\n\n[agent stopped after 12 iterations]'})}\n\n"
    yield f"data: {json.dumps({'type':'done'})}\n\n"


HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AyhanX-Agent</title>
<style>
:root{--bg:#080b12;--panel:#10141e;--panel-2:#161b27;--border:#232a3d;--border-2:#2f3849;
--text:#e8eef7;--dim:#8b95a8;--mute:#5c6577;
--accent:#5eead4;--accent-2:#2dd4bf;--glow:rgba(94,234,212,.15);
--red:#f87171;--amber:#fbbf24;--green:#34d399;--violet:#a78bfa;--blue:#60a5fa}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:var(--bg);color:var(--text);
font:15px/1.6 -apple-system,BlinkMacSystemFont,"Inter","Segoe UI",Roboto,sans-serif;
-webkit-font-smoothing:antialiased}
body::before{content:'';position:fixed;inset:-50%;z-index:0;pointer-events:none;
background:radial-gradient(circle at 20% 10%,rgba(94,234,212,.10),transparent 40%),
radial-gradient(circle at 80% 90%,rgba(167,139,250,.08),transparent 40%);
animation:drift 24s ease-in-out infinite alternate}
@keyframes drift{0%{transform:translate(0,0) scale(1)}100%{transform:translate(3%,-2%) scale(1.05)}}
#app{position:relative;z-index:1;display:flex;height:100vh}
.sidebar{width:270px;background:rgba(16,20,30,.6);backdrop-filter:blur(20px);
border-right:1px solid var(--border);display:flex;flex-direction:column;
flex-shrink:0;transition:transform .3s cubic-bezier(.4,0,.2,1)}
.sidebar-head{padding:18px 18px 14px}
.brand{display:flex;align-items:center;gap:10px;margin-bottom:18px}
.brand-icon{width:28px;height:28px;border-radius:8px;
background:linear-gradient(135deg,var(--accent),var(--accent-2));
display:flex;align-items:center;justify-content:center;
color:#0a0e14;font-weight:700;font-size:16px;
box-shadow:0 0 16px var(--glow)}
.brand-name{font-weight:600;font-size:14px}
.brand-ver{font-size:11px;color:var(--mute)}
.new-btn{width:100%;padding:10px 14px;border-radius:10px;
background:linear-gradient(135deg,rgba(94,234,212,.15),rgba(45,212,191,.08));
border:1px solid rgba(94,234,212,.3);color:var(--accent);
font-weight:600;font-size:13px;cursor:pointer;
display:flex;align-items:center;justify-content:center;gap:8px;
transition:all .2s;font-family:inherit}
.new-btn:hover{background:linear-gradient(135deg,rgba(94,234,212,.25),rgba(45,212,191,.15));
box-shadow:0 0 20px var(--glow);transform:translateY(-1px)}
.convs{flex:1;overflow-y:auto;padding:8px 10px}
.conv-item{padding:10px 12px;border-radius:10px;cursor:pointer;
display:flex;align-items:center;gap:8px;font-size:13px;color:var(--dim);
transition:all .15s;margin-bottom:2px}
.conv-item:hover{background:rgba(255,255,255,.04);color:var(--text)}
.conv-item.active{background:rgba(94,234,212,.1);color:var(--accent);
border:1px solid rgba(94,234,212,.2)}
.conv-item .title{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.conv-item .del{opacity:0;color:var(--red);font-size:16px;padding:0 2px;
background:none;border:none;cursor:pointer}
.conv-item:hover .del{opacity:.7}
.empty-state{padding:40px 20px;text-align:center;color:var(--mute);font-size:12px}
.empty-state .icon{font-size:32px;margin-bottom:8px;opacity:.5}
.sidebar-foot{padding:12px 14px;border-top:1px solid var(--border)}
.provider-btn{width:100%;padding:10px 12px;border-radius:10px;
background:rgba(255,255,255,.03);border:1px solid var(--border);
color:var(--text);font-size:12.5px;cursor:pointer;
display:flex;align-items:center;gap:8px;transition:all .15s;font-family:inherit}
.provider-btn:hover{background:rgba(255,255,255,.06);border-color:var(--border-2)}
.dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;background:var(--green);
box-shadow:0 0 8px currentColor}
.dot.deepseek{background:var(--blue);box-shadow:0 0 8px var(--blue)}
.dot.openrouter{background:var(--violet);box-shadow:0 0 8px var(--violet)}
.dot.groq{background:var(--amber);box-shadow:0 0 8px var(--amber)}
.dot.google{background:var(--red);box-shadow:0 0 8px var(--red)}
.dot.local{background:var(--green);box-shadow:0 0 8px var(--green)}
.provider-name{flex:1;text-align:left;font-weight:500}
.main{flex:1;display:flex;flex-direction:column;min-width:0}
.header{padding:14px 24px;border-bottom:1px solid var(--border);
display:flex;align-items:center;gap:12px;
background:rgba(11,15,23,.6);backdrop-filter:blur(20px)}
.menu-btn{display:none;background:none;border:none;color:var(--text);
font-size:20px;cursor:pointer;padding:6px}
.model-sel{padding:6px 12px;border-radius:8px;background:var(--panel);
border:1px solid var(--border);color:var(--text);font-size:13px;
cursor:pointer;display:flex;align-items:center;gap:8px;
transition:all .15s;font-family:inherit}
.model-sel:hover{background:var(--panel-2);border-color:var(--border-2)}
.model-sel .chev{font-size:10px;color:var(--mute)}
.spacer{flex:1}
.mode-toggle{padding:6px 14px;border-radius:999px;font-size:12px;font-weight:600;
background:rgba(52,211,153,.15);border:1px solid rgba(52,211,153,.3);
color:var(--green);cursor:pointer;display:flex;align-items:center;gap:6px;
transition:all .2s;font-family:inherit}
.mode-toggle:hover{filter:brightness(1.15)}
.mode-toggle.agent{background:rgba(251,191,36,.15);
border-color:rgba(251,191,36,.3);color:var(--amber)}
.mode-dot{width:6px;height:6px;border-radius:50%;background:currentColor;
box-shadow:0 0 6px currentColor}
.icon-btn{background:none;border:1px solid var(--border);color:var(--dim);
width:34px;height:34px;border-radius:8px;cursor:pointer;font-size:16px;
display:flex;align-items:center;justify-content:center;transition:all .15s}
.icon-btn:hover{background:var(--panel);color:var(--text);border-color:var(--border-2)}
.chat{flex:1;overflow-y:auto;padding:8px 0 140px;scroll-behavior:smooth}
.chat::-webkit-scrollbar{width:8px}
.chat::-webkit-scrollbar-thumb{background:var(--border-2);border-radius:4px}
.welcome{max-width:820px;margin:100px auto 0;padding:0 32px;text-align:center;animation:fadeUp .6s ease-out}
@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
.welcome-icon{width:64px;height:64px;border-radius:18px;margin:0 auto 24px;
background:linear-gradient(135deg,var(--accent),var(--accent-2));
display:flex;align-items:center;justify-content:center;font-size:28px;
color:#0a0e14;font-weight:700;
box-shadow:0 0 40px var(--glow),0 8px 32px rgba(0,0,0,.3)}
.welcome h1{font-size:36px;font-weight:700;margin-bottom:8px;letter-spacing:-.5px;
background:linear-gradient(135deg,var(--text),var(--accent));
-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent}
.welcome p{color:var(--dim);font-size:15px;margin-bottom:40px}
.suggestions{display:grid;grid-template-columns:repeat(2,1fr);gap:12px;margin-top:32px}
.sug{padding:14px 18px;background:rgba(255,255,255,.02);
border:1px solid var(--border);border-radius:12px;color:var(--dim);
font-size:13.5px;text-align:left;cursor:pointer;transition:all .2s;font-family:inherit}
.sug:hover{background:rgba(94,234,212,.06);border-color:rgba(94,234,212,.3);
color:var(--text);transform:translateY(-1px)}
.message{max-width:820px;margin:0 auto;padding:14px 32px;display:flex;gap:16px;
animation:fadeUp .3s ease-out}
.message+.message{padding-top:4px}
.msg-body{flex:1;min-width:0;line-height:1.7;word-wrap:break-word}
.msg-role{font-size:11px;font-weight:600;color:var(--mute);
margin-bottom:4px;letter-spacing:.5px;text-transform:uppercase}
.msg-user{justify-content:flex-end}
.msg-user .msg-body{flex:0 1 auto;max-width:75%;
background:linear-gradient(135deg,rgba(94,234,212,.08),rgba(45,212,191,.04));
border:1px solid rgba(94,234,212,.2);border-radius:16px;padding:10px 16px;
color:var(--text);white-space:pre-wrap}
.msg-user .msg-role{display:none}
.msg-ai .msg-role{color:var(--accent)}
.msg-ai .msg-body p{margin-bottom:12px}
.msg-ai .msg-body p:last-child{margin-bottom:0}
.msg-ai .msg-body code{background:var(--panel-2);padding:2px 6px;border-radius:5px;
font:13px/1.4 "SF Mono","JetBrains Mono",Menlo,monospace;color:var(--accent)}
.msg-ai .msg-body pre{background:#060810;border:1px solid var(--border);
padding:14px 16px;border-radius:10px;overflow-x:auto;margin:12px 0;
font:13px/1.5 "SF Mono","JetBrains Mono",Menlo,monospace}
.msg-ai .msg-body pre code{background:none;padding:0;color:var(--text)}
.msg-ai .msg-body ul,.msg-ai .msg-body ol{margin:8px 0 12px 24px}
.msg-ai .msg-body li{margin:4px 0}
.msg-ai .msg-body h1,.msg-ai .msg-body h2,.msg-ai .msg-body h3{
margin:16px 0 8px;font-weight:600;color:var(--text)}
.msg-ai .msg-body h1{font-size:1.4em}
.msg-ai .msg-body h2{font-size:1.2em}
.msg-ai .msg-body h3{font-size:1.1em}
.msg-ai .msg-body a{color:var(--accent);text-decoration:none;border-bottom:1px solid transparent}
.msg-ai .msg-body a:hover{border-bottom-color:var(--accent)}
.msg-ai .msg-body strong{color:var(--text);font-weight:600}
.msg-ai .msg-body blockquote{border-left:3px solid var(--border-2);
padding-left:14px;color:var(--dim);margin:12px 0}
.tool-cards{margin:8px 0 0 32px}
.tool-card{background:rgba(251,191,36,.06);border:1px solid rgba(251,191,36,.2);
border-radius:8px;padding:10px 14px;margin:6px 0;font-size:12px;
font-family:"SF Mono","JetBrains Mono",Menlo,monospace}
.tool-card .tool-name{color:var(--amber);font-weight:600}
.tool-card .tool-args{color:var(--mute);margin-left:8px}
.tool-card .tool-result{color:var(--text);margin-top:6px;padding-top:6px;
border-top:1px solid rgba(251,191,36,.15);white-space:pre-wrap;
max-height:120px;overflow-y:auto;font-size:11.5px;line-height:1.5}
.msg-err{background:rgba(248,113,113,.08);border:1px solid rgba(248,113,113,.3);
border-radius:10px;padding:12px 16px;color:var(--red);font-size:13px}
.cursor{display:inline-block;width:7px;height:16px;background:var(--accent);
vertical-align:middle;margin-left:2px;animation:blink 1s steps(2) infinite;border-radius:2px}
@keyframes blink{0%,50%{opacity:1}51%,100%{opacity:0}}
.composer-wrap{position:fixed;bottom:0;left:270px;right:0;
padding:20px 24px 22px;background:linear-gradient(transparent,var(--bg) 30%);z-index:10}
.composer{max-width:820px;margin:0 auto}
.composer-inner{background:rgba(16,20,30,.85);backdrop-filter:blur(20px);
border:1px solid var(--border);border-radius:18px;padding:8px 8px 8px 18px;
display:flex;align-items:flex-end;gap:8px;transition:all .2s;
box-shadow:0 4px 24px rgba(0,0,0,.3)}
.composer-inner:focus-within{border-color:rgba(94,234,212,.4);
box-shadow:0 0 0 3px var(--glow),0 4px 24px rgba(0,0,0,.4)}
#input{flex:1;background:none;border:none;outline:none;color:var(--text);
font:inherit;resize:none;max-height:200px;padding:8px 0;line-height:1.6}
#input::placeholder{color:var(--mute)}
.send-btn{width:38px;height:38px;border-radius:12px;border:none;cursor:pointer;
background:linear-gradient(135deg,var(--accent),var(--accent-2));
color:#0a0e14;font-size:18px;font-weight:700;
display:flex;align-items:center;justify-content:center;transition:all .2s;
flex-shrink:0;font-family:inherit}
.send-btn:hover:not(:disabled){transform:scale(1.05);box-shadow:0 0 20px var(--glow)}
.send-btn:disabled{background:var(--panel-2);color:var(--mute);cursor:not-allowed}
.composer-hint{max-width:820px;margin:8px auto 0;padding:0 4px;
display:flex;justify-content:space-between;font-size:11px;color:var(--mute)}
#status{color:var(--accent)}
.modal{position:fixed;inset:0;background:rgba(0,0,0,.6);backdrop-filter:blur(4px);
z-index:100;display:none;align-items:center;justify-content:center;padding:20px;
animation:fadeIn .15s}
.modal.open{display:flex}
@keyframes fadeIn{from{opacity:0}to{opacity:1}}
.modal-content{background:var(--panel);border:1px solid var(--border-2);
border-radius:16px;max-width:480px;width:100%;max-height:80vh;
display:flex;flex-direction:column;box-shadow:0 24px 64px rgba(0,0,0,.5)}
.modal-head{padding:18px 22px;border-bottom:1px solid var(--border);
display:flex;justify-content:space-between;align-items:center}
.modal-title{font-size:15px;font-weight:600}
.modal-close{background:none;border:none;color:var(--mute);cursor:pointer;font-size:20px;padding:4px}
.modal-close:hover{color:var(--text)}
.modal-body{padding:12px;overflow-y:auto}
.modal-opt{padding:12px 16px;border-radius:10px;cursor:pointer;
display:flex;align-items:center;gap:12px;font-size:13.5px;color:var(--text);
transition:background .15s;border:1px solid transparent}
.modal-opt:hover{background:rgba(255,255,255,.05)}
.modal-opt.active{background:rgba(94,234,212,.1);border-color:rgba(94,234,212,.25);color:var(--accent)}
.modal-opt .opt-main{flex:1;font-weight:500}
.modal-opt .opt-sub{font-size:11px;color:var(--mute);font-family:"SF Mono","JetBrains Mono",Menlo,monospace}
.toast{position:fixed;bottom:100px;left:50%;transform:translateX(-50%) translateY(20px);
background:var(--panel-2);border:1px solid var(--border-2);
padding:10px 20px;border-radius:10px;font-size:13px;color:var(--text);
opacity:0;pointer-events:none;transition:all .3s;z-index:200;
box-shadow:0 8px 24px rgba(0,0,0,.4)}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
.toast.err{border-color:rgba(248,113,113,.4);color:var(--red)}
@media(max-width:768px){
.sidebar{position:fixed;inset:0 auto 0 0;z-index:50;transform:translateX(-100%)}
.sidebar.open{transform:translateX(0)}
.menu-btn{display:block}
.composer-wrap{left:0;padding:16px 12px}
.suggestions{grid-template-columns:1fr}
.welcome h1{font-size:28px}
.welcome{margin-top:60px}
.msg-user .msg-body{max-width:90%}
}
</style>
</head>
<body>
<div id="app">
<aside class="sidebar" id="sidebar">
<div class="sidebar-head">
<div class="brand">
<div class="brand-icon">◆</div>
<div>
<div class="brand-name">AyhanX-Agent</div>
<div class="brand-ver">v<span id="ver">4.0.0</span></div>
</div>
</div>
<button class="new-btn" onclick="newConversation()"><span>+</span><span>New chat</span></button>
</div>
<div class="convs" id="convs"></div>
<div class="sidebar-foot">
<button class="provider-btn" onclick="openProviderPicker()">
<span class="dot" id="provider-dot"></span>
<span class="provider-name" id="provider-name">DeepSeek</span>
<span style="color:var(--mute);font-size:12px">⇄</span>
</button>
</div>
</aside>
<main class="main">
<header class="header">
<button class="menu-btn" onclick="toggleSidebar()">☰</button>
<button class="model-sel" onclick="openModelPicker()">
<span id="model-name">deepseek-chat</span>
<span class="chev">▾</span>
</button>
<div class="spacer"></div>
<button class="mode-toggle" id="mode-toggle" onclick="toggleAgent()">
<span class="mode-dot"></span><span id="mode-text">Chat</span>
</button>
<button class="icon-btn" onclick="newConversation()" title="New chat">⊕</button>
</header>
<div class="chat" id="chat">
<div class="welcome" id="welcome">
<div class="welcome-icon">◆</div>
<h1>AyhanX-Agent</h1>
<p>Premium AI chat · full terminal access in Agent mode</p>
<div class="suggestions">
<button class="sug" onclick="suggest('Write a Python script that finds duplicate files and run it')">📝 Write & run a duplicate finder</button>
<button class="sug" onclick="suggest('List my home directory and tell me what is here')">📁 Explore my home directory</button>
<button class="sug" onclick="suggest('Create a FastAPI server in a folder called api and run it')">🚀 Build a FastAPI server</button>
<button class="sug" onclick="suggest('Explain quantum computing in simple terms')">💡 Explain quantum computing</button>
</div>
</div>
</div>
<div class="composer-wrap">
<div class="composer">
<div class="composer-inner">
<textarea id="input" placeholder="Message AyhanX-Agent..." rows="1"
onkeydown="handleKey(event)" oninput="autoResize(this)"></textarea>
<button class="send-btn" id="send-btn" onclick="sendMessage()" disabled>↑</button>
</div>
</div>
<div class="composer-hint">
<span>Enter send · Shift+Enter newline</span>
<span id="status">Ready</span>
</div>
</div>
</main>
</div>
<div class="modal" id="modal" onclick="closeModal(event)">
<div class="modal-content" onclick="event.stopPropagation()">
<div class="modal-head">
<div class="modal-title" id="modal-title">Select</div>
<button class="modal-close" onclick="closeModal()">×</button>
</div>
<div class="modal-body" id="modal-body"></div>
</div>
</div>
<div class="toast" id="toast"></div>

<script>
const state = {provider:"deepseek", model:"deepseek-chat", agent:false, convId:null,
                messages:[], streaming:false, config:{}};
const $ = s => document.querySelector(s);
const input = $('#input'), sendBtn = $('#send-btn'), chat = $('#chat'),
      status = $('#status'), welcome = $('#welcome');

function escapeHtml(s){return s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function md(text){
  if(!text) return '';
  let s = escapeHtml(text);
  s = s.replace(/```(\w*)\n?([\s\S]*?)```/g,(m,lang,code)=>`<pre><code>${code}</code></pre>`);
  s = s.replace(/`([^`]+)`/g,'<code>$1</code>');
  s = s.replace(/\*\*([^*]+)\*\*/g,'<strong>$1</strong>');
  s = s.replace(/\*([^*]+)\*/g,'<em>$1</em>');
  s = s.replace(/^### (.+)$/gm,'<h3>$1</h3>');
  s = s.replace(/^## (.+)$/gm,'<h2>$1</h2>');
  s = s.replace(/^# (.+)$/gm,'<h1>$1</h1>');
  s = s.replace(/^- (.+)$/gm,'<li>$1</li>');
  s = s.replace(/(<li>.*<\/li>\n?)+/g,m=>`<ul>${m}</ul>`);
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g,'<a href="$2" target="_blank">$1</a>');
  s = s.replace(/^&gt; (.+)$/gm,'<blockquote>$1</blockquote>');
  s = s.split('\n\n').map(p=>p.trim()).filter(Boolean).map(p=>{
    if(/^<(h[1-6]|ul|ol|pre|blockquote|li)/.test(p)) return p;
    return `<p>${p.replace(/\n/g,'<br>')}</p>`;
  }).join('');
  return s;
}

async function api(path, opts={}){
  const r = await fetch(path, {headers:{'Content-Type':'application/json'}, ...opts});
  if(!r.ok) throw new Error(await r.text());
  return r.json();
}

async function loadConfig(){
  const c = await api('/api/config');
  state.config = c; state.provider = c.provider; state.model = c.model; state.agent = c.agent_mode;
  $('#ver').textContent = c.version;
  $('#provider-name').textContent = c.provider_label;
  $('#provider-dot').className = 'dot ' + (c.is_local ? 'local' : c.provider);
  $('#model-name').textContent = c.model;
  updateModeBtn();
}

function updateModeBtn(){
  const b = $('#mode-toggle');
  b.classList.toggle('agent', state.agent);
  $('#mode-text').textContent = state.agent ? 'Agent' : 'Chat';
}

async function loadConversations(){
  const list = await api('/api/conversations');
  const el = $('#convs');
  if(!list.length){
    el.innerHTML = '<div class="empty-state"><div class="icon">💬</div>No conversations yet</div>';
    return;
  }
  el.innerHTML = list.map(c => `
    <div class="conv-item ${c.id===state.convId?'active':''}" data-id="${c.id}">
      <span class="title">${escapeHtml(c.id)}</span>
      <button class="del" onclick="event.stopPropagation();delConv('${c.id}')" title="Delete">×</button>
    </div>`).join('');
  el.querySelectorAll('.conv-item').forEach(item => {
    item.onclick = () => loadConversation(item.dataset.id);
  });
}

async function loadConversation(id){
  const data = await api(`/api/conversations/${id}`);
  state.convId = id; state.messages = data.messages;
  hideWelcome(); chat.innerHTML = '';
  for(const m of data.messages){
    if(m.role === 'user') addMessage('user', m.content);
    else if(m.role === 'assistant') addMessage('ai', m.content);
  }
  await loadConversations();
  scrollDown();
}

async function delConv(id){
  await api(`/api/conversations/${id}`, {method:'DELETE'});
  if(state.convId === id) newConversation();
  await loadConversations();
}

function hideWelcome(){ if(welcome) welcome.style.display = 'none'; }
function scrollDown(){ chat.scrollTop = chat.scrollHeight; }

function addMessage(role, content){
  hideWelcome();
  const el = document.createElement('div');
  el.className = `message msg-${role}`;
  if(role === 'user'){
    el.innerHTML = `<div class="msg-body">${escapeHtml(content)}</div>`;
  } else {
    el.innerHTML = `<div class="msg-body"><div class="msg-role">Assistant</div><div class="md"></div></div>`;
    el.querySelector('.md').innerHTML = md(content);
  }
  chat.appendChild(el);
  scrollDown();
  return el;
}

function showToast(msg, isErr){
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast show' + (isErr ? ' err' : '');
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.className = 'toast', 2500);
}

function setStatus(s){ status.textContent = s; }
function suggest(text){ input.value = text; autoResize(input); sendMessage(); }

function autoResize(el){
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 200) + 'px';
  sendBtn.disabled = !el.value.trim() || state.streaming;
}

function handleKey(e){
  if(e.key === 'Enter' && !e.shiftKey){ e.preventDefault(); sendMessage(); }
}

async function sendMessage(){
  const text = input.value.trim();
  if(!text || state.streaming) return;
  input.value = ''; autoResize(input);
  addMessage('user', text);
  state.messages.push({role:'user', content:text});
  state.streaming = true; sendBtn.disabled = true; setStatus('Thinking…');

  const aiEl = addMessage('ai', '');
  const mdEl = aiEl.querySelector('.md');
  let answer = '';
  let toolCards = [];

  try {
    const r = await fetch('/api/chat', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({conversation_id: state.convId, message: text, agent: state.agent})
    });
    if(!r.ok) throw new Error('HTTP ' + r.status);
    const reader = r.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    setStatus('Streaming…');

    while(true){
      const {done, value} = await reader.read();
      if(done) break;
      buf += decoder.decode(value, {stream:true});
      let idx;
      while((idx = buf.indexOf('\n\n')) >= 0){
        const chunk = buf.slice(0, idx); buf = buf.slice(idx + 2);
        for(const line of chunk.split('\n')){
          if(!line.startsWith('data: ')) continue;
          try {
            const obj = JSON.parse(line.slice(6));
            if(obj.type === 'start'){ state.convId = obj.conversation_id; }
            else if(obj.type === 'delta'){
              answer += obj.text;
              mdEl.innerHTML = md(answer) + '<span class="cursor"></span>';
              scrollDown();
            }
            else if(obj.type === 'tool'){
              const card = document.createElement('div');
              card.className = 'tool-card';
              card.innerHTML = `<div><span class="tool-name">⚙ ${obj.name}</span><span class="tool-args">${escapeHtml(JSON.stringify(obj.args).slice(0,100))}</span></div><div class="tool-result">running...</div>`;
              let tc = document.createElement('div');
              tc.className = 'tool-cards';
              tc.appendChild(card);
              aiEl.querySelector('.msg-body').appendChild(tc);
              toolCards.push({card, name: obj.name});
              scrollDown();
            }
            else if(obj.type === 'tool_result'){
              if(toolCards.length){
                const last = toolCards[toolCards.length-1];
                const resultDiv = last.card.querySelector('.tool-result');
                if(resultDiv) resultDiv.textContent = String(obj.text).slice(0, 500);
              }
            }
            else if(obj.type === 'error'){
              mdEl.innerHTML = `<div class="msg-err">${escapeHtml(obj.message)}</div>`;
              setStatus('Error');
            }
            else if(obj.type === 'done'){
              mdEl.innerHTML = md(answer);
              setStatus('Ready');
            }
          } catch(_){}
        }
      }
    }

    if(answer) state.messages.push({role:'assistant', content:answer});
    await loadConversations();
  } catch(e){
    mdEl.innerHTML = `<div class="msg-err">⚠ ${escapeHtml(e.message)}</div>`;
    setStatus('Error');
  } finally {
    state.streaming = false;
    sendBtn.disabled = !input.value.trim();
    setStatus('Ready');
    input.focus();
  }
}

function openModal(title, bodyHtml, onSelect){
  $('#modal-title').textContent = title;
  const body = $('#modal-body');
  body.innerHTML = bodyHtml;
  body.querySelectorAll('[data-value]').forEach(el => {
    el.onclick = () => { onSelect(el.dataset.value); closeModal(); };
  });
  $('#modal').classList.add('open');
}

function closeModal(e){
  if(e && e.target !== $('#modal') && !e.target.classList.contains('modal-close')) return;
  $('#modal').classList.remove('open');
}

async function openProviderPicker(){
  const list = await api('/api/providers');
  const html = list.map(p => `
    <div class="modal-opt ${p.active ? 'active' : ''}" data-value="${p.name}">
      <span class="dot ${p.local ? 'local' : p.name}"></span>
      <div style="flex:1">
        <div class="opt-main">${p.label}</div>
        <div class="opt-sub">${p.model}</div>
      </div>
      ${p.active ? '<span style="color:var(--accent);font-size:16px">✓</span>' : ''}
    </div>`).join('');
  openModal('Switch provider', html, async (name) => {
    try {
      await api('/api/switch', {method:'POST', body: JSON.stringify({provider:name})});
      await loadConfig();
      showToast('Switched to ' + name);
    } catch(e){ showToast('Failed: ' + e.message, true); }
  });
}

async function openModelPicker(){
  const data = await api('/api/models');
  if(!data.models.length){ showToast('No models available', true); return; }
  const html = data.models.map(m => `
    <div class="modal-opt ${m === data.current ? 'active' : ''}" data-value="${m}">
      <div style="flex:1"><div class="opt-main">${escapeHtml(m)}</div></div>
      ${m === data.current ? '<span style="color:var(--accent);font-size:16px">✓</span>' : ''}
    </div>`).join('');
  openModal('Select model', html, async (model) => {
    try {
      await api('/api/model', {method:'POST', body: JSON.stringify({model})});
      state.model = model;
      $('#model-name').textContent = model;
      showToast('Model → ' + model);
    } catch(e){ showToast('Failed: ' + e.message, true); }
  });
}

async function toggleAgent(){
  state.agent = !state.agent;
  try {
    await api('/api/agent', {method:'POST', body: JSON.stringify({enabled: state.agent})});
    updateModeBtn();
    showToast(state.agent ? 'Agent mode ON — full terminal access' : 'Agent mode OFF');
  } catch(e){ showToast('Failed: ' + e.message, true); }
}

function newConversation(){
  state.convId = null; state.messages = []; chat.innerHTML = '';
  if(welcome){ chat.appendChild(welcome); welcome.style.display = ''; }
  loadConversations(); input.focus();
}

function toggleSidebar(){ $('#sidebar').classList.toggle('open'); }

(async function init(){
  await loadConfig();
  await loadConversations();
  input.focus();
  setStatus('Ready');
})();
</script>
</body>
</html>
"""

@app.get("/", response_class=HTMLResponse)
def index(): return HTML

@app.get("/health")
def health(): return {"ok": True, "version": VERSION}

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "8080"))
    host = os.environ.get("HOST", "0.0.0.0")
    print(f"\n  ◆ AyhanX-Agent web UI")
    print(f"  → http://localhost:{port}\n")
    uvicorn.run(app, host=host, port=port, log_level="warning")
PYEOF
}

# ============================================================================
#  COMMANDS
# ============================================================================
cmd_tui() { cd "$APP_DIR"; PYTHONPATH="$APP_DIR" "$VENV/bin/python" -m runner.tui || true; }

cmd_web() {
  local port="${1:-8080}"
  section "Starting web UI on :$port"
  local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s  →%s http://localhost:%s\n' "$B4" "$RS" "$port"
  [[ -n "$ip" ]] && printf '%s  →%s http://%s:%s  (LAN)\n' "$B4" "$RS" "$ip" "$port"
  printf '%s  Ctrl+C to stop%s\n\n' "$DM" "$RS"
  cd "$APP_DIR"
  PORT="$port" PYTHONPATH="$APP_DIR" exec "$VENV/bin/python" -m runner.server
}

cmd_switch() {
  local name="${1:-}"
  [[ -z "$name" ]] && {
    err "usage: $0 switch <provider>"
    [[ -f "$PROVIDERS_FILE" ]] && \
      "$VENV/bin/python" -c "import json;print('\n'.join('  · '+k for k in json.load(open('$PROVIDERS_FILE'))))" 2>/dev/null || true
    exit 1
  }
  if [[ -f "$PROVIDERS_FILE" ]]; then
    "$VENV/bin/python" - "$PROVIDERS_FILE" "$PROVIDER_FILE" "$name" <<'PY'
import json, sys
pfile, active, name = sys.argv[1:4]
data = json.loads(open(pfile).read())
if name not in data:
    print(f"unknown provider: {name}", file=sys.stderr)
    print(f"available: {', '.join(data)}", file=sys.stderr); sys.exit(1)
open(active, "w").write(name)
print(f"→ switched to {name}")
print(f"  model    {data[name]['model']}")
print(f"  endpoint {data[name]['url']}")
PY
  else
    printf '%s\n' "$name" > "$PROVIDER_FILE"; ok "provider → $name"
  fi
}

post_menu() {
  echo; rule
  printf '  %s◆%s %sWhat next?%s   %s[r]%s resume   %s[n]%s new   %s[w]%s web UI   %s[p]%s provider   %s[q]%s quit\n' \
    "$V1" "$RS" "$BD" "$RS" "$C1" "$RS" "$C1" "$RS" "$C1" "$RS" "$C1" "$RS" "$C1" "$RS"
  local key=""; read -r -s -n 1 key || key="q"; echo; printf '%s' "$key"
}

switch_menu() {
  [[ ! -f "$PROVIDERS_FILE" ]] && { warn "no providers.json"; return 1; }
  echo; section "Switch provider"
  "$VENV/bin/python" - "$PROVIDERS_FILE" "$PROVIDER_FILE" <<'PY'
import json, sys
pfile, active = sys.argv[1:3]
data = json.loads(open(pfile).read())
try: current = open(active).read().strip()
except Exception: current = ""
names = list(data)
for i, n in enumerate(names, 1):
    marker = "◆" if n == current else " "
    print(f"    {i})  {marker} {n:<12} → {data[n]['model']}")
print()
choice = input("  > ").strip()
if choice.isdigit():
    i = int(choice) - 1
    if 0 <= i < len(names):
        name = names[i]; open(active, "w").write(name)
        print(f"→ switched to {name}")
        print(f"  model    {data[name]['model']}")
        print(f"  endpoint {data[name]['url']}")
PY
}

chat_loop() {
  local next="new" choice
  while true; do
    clear; print_logo; print_tagline
    export AYHANX_START="$next"
    cmd_tui
    choice="$(post_menu)"
    case "$choice" in
      r|R) next="resume" ;;
      w|W) cmd_web 8080 ;;
      p|P) switch_menu; sleep 1; next="new" ;;
      q|Q) break ;;
      *)   next="new" ;;
    esac
  done
}

cmd_ask() {
  local prompt="$*"; [[ -z "$prompt" ]] && { err "empty prompt"; exit 1; }
  "$VENV/bin/python" - "$prompt" <<'PY'
import json, os, sys
import httpx
p = sys.argv[1]
provider = os.environ.get("AYHANX_PROVIDER", "deepseek")
base = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
h = {"Authorization": f"Bearer {os.environ.get('DEEPSEEK_API_KEY', 'local')}", "Content-Type": "application/json"}
if provider == "openrouter":
    h["HTTP-Referer"] = "https://github.com/AyhanMansur/AyhanX-Agent"
    h["X-Title"] = "AyhanX-Agent"
r = httpx.post(f"{base}/chat/completions", headers=h,
               json={"model": os.environ.get("DEEPSEEK_MODEL", "deepseek-chat"),
                     "messages": [{"role": "user", "content": p}]}, timeout=120)
if r.status_code >= 400:
    try: msg = r.json().get("error", {}).get("message", r.text)
    except Exception: msg = r.text
    hints = {401: "invalid key", 402: "no balance", 404: "model not found", 429: "rate limited"}
    hint = hints.get(r.status_code, "")
    if provider in ("ollama","lmstudio","vllm","llamacpp","localai"): hint = "is the server running?"
    print(f"HTTP {r.status_code}: {msg}" + (f" ({hint})" if hint else ""), file=sys.stderr); sys.exit(1)
print(r.json()["choices"][0]["message"]["content"])
PY
}

cmd_health() {
  section "Connection check"
  "$VENV/bin/python" - <<'PY'
import os
import httpx
provider = os.environ.get("AYHANX_PROVIDER", "deepseek")
base = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
model = os.environ.get("DEEPSEEK_MODEL", "deepseek-chat")
h = {"Authorization": f"Bearer {os.environ.get('DEEPSEEK_API_KEY', 'local')}", "Content-Type": "application/json"}
if provider == "openrouter":
    h["HTTP-Referer"] = "https://github.com/AyhanMansur/AyhanX-Agent"
    h["X-Title"] = "AyhanX-Agent"
G, R, M, N = "\033[38;5;84m", "\033[38;5;203m", "\033[38;5;245m", "\033[0m"
print(f"  {M}provider{N}  {provider}")
print(f"  {M}endpoint{N}  {base}")
print(f"  {M}model{N}     {model}")
try:
    if provider in ("ollama","lmstudio","vllm","llamacpp","localai"):
        try:
            mr = httpx.get(f"{base}/models", headers=h, timeout=10)
            if mr.status_code == 200:
                ids = [m["id"] for m in mr.json().get("data", [])]
                if ids: print(f"  {M}models{N}    {', '.join(ids[:4])}{' …' if len(ids)>4 else ''}")
        except Exception: pass
    r = httpx.post(f"{base}/chat/completions", headers=h, timeout=30,
                   json={"model": model, "max_tokens": 5, "messages": [{"role": "user", "content": "say OK"}]})
    print(f"  {M}status{N}    {r.status_code}")
    j = r.json()
    if "choices" in j:
        print(f"  {M}reply{N}     {j['choices'][0]['message']['content']!r}")
        print(f"  {G}✔ connected{N}")
    else:
        print(f"  {M}body{N}      {r.text[:300]}")
        print(f"  {R}✘ failed{N}")
except Exception as e:
    hint = "  → is the server running?" if provider in ("ollama","lmstudio","vllm","llamacpp","localai") else ""
    print(f"  {R}✘ {type(e).__name__}: {e}{N}{hint}")
PY
}

cmd_config() {
  section "Files"
  info "provider ${AYHANX_PROVIDER:-deepseek}"
  info "config   $CONFIG_FILE"
  info "env      $ENV_FILE"
  info "providers $PROVIDERS_FILE"
  info "chats    $CHATS_DIR"
  echo
  [[ -f "$PROVIDERS_FILE" ]] && { section "Providers"; cat "$PROVIDERS_FILE"; echo; }
  [[ -f "$CONFIG_FILE" ]] && { section "Config"; cat "$CONFIG_FILE"; echo; }
}

cmd_version() {
  section "Version"
  info "AyhanX-Agent  $VERSION"
  info "repo       $REPO_URL"
  info "provider   ${AYHANX_PROVIDER:-deepseek}"
  info "app dir    $APP_DIR"
  [[ -x "$VENV/bin/python" ]] && info "python     $("$VENV/bin/python" --version 2>&1)"
}

# ============================================================================
#  MAIN
# ============================================================================
main() {
  mkdir -p "$APP_DIR"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider)   shift; export AYHANX_PROVIDER="${1:-}"; shift || break ;;
      --provider=*) export AYHANX_PROVIDER="${1#*=}"; shift ;;
      --)           shift; break ;;
      ask|health|config|version|switch|chat|tui|web) break ;;
      *)            break ;;
    esac
  done

  case "${1:-chat}" in
    ask)     shift; ensure_env; ensure_key; cmd_ask "$@" ;;
    health)  ensure_env; ensure_key; cmd_health ;;
    config)  cmd_config ;;
    version) cmd_version ;;
    switch)  shift; ensure_env; ensure_key; cmd_switch "$@" ;;
    web)
      shift
      ensure_env; ensure_key
      section "Preparing web UI"
      write_tools; write_tui; write_server
      ok "runner ready"
      sleep 0.2
      cmd_web "$@"
      ;;
    chat|tui|"")
      ensure_env; ensure_key
      section "Starting"
      write_tools; write_tui; write_server
      ok "runner ready"
      sleep 0.2
      chat_loop
      print_outro
      ;;
    *)
      err "unknown mode: $1"
      info "usage: $0 [--provider NAME] [chat|web|ask|health|config|version|switch]"
      exit 1
      ;;
  esac
}

main "$@"
