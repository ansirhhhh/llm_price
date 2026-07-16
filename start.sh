#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
VENV_PY="$BACKEND_DIR/venv/bin/python"
PORT=8000

echo "========================================"
echo "  AI Model Price Compare Platform"
echo "========================================"
echo ""

# ------------------------------------------------------------------
# [0/4] Cleanup: kill anything listening on port $PORT plus any
# python processes whose command line looks like this project
# (catches: uvicorn reloader, --reload workers, gunicorn, stray spawn).
# ------------------------------------------------------------------
echo "[0/4] Cleaning up any processes on port $PORT..."
LISTEN_PIDS=""
if command -v lsof >/dev/null 2>&1; then
    LISTEN_PIDS="$(lsof -t -iTCP:$PORT -sTCP:LISTEN -n -P 2>/dev/null | sort -u || true)"
elif command -v ss >/dev/null 2>&1; then
    LISTEN_PIDS="$(ss -ltnp 2>/dev/null \
        | awk -v p=":$PORT" '$4 ~ p {print $0}' \
        | grep -oE 'pid=[0-9]+' \
        | cut -d= -f2 \
        | sort -u || true)"
elif command -v fuser >/dev/null 2>&1; then
    LISTEN_PIDS="$(fuser ${PORT}/tcp 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u || true)"
fi
killed_any=0
kill_pid_safe() {
    local pid="$1"
    [ -z "$pid" ] && return
    kill -0 "$pid" 2>/dev/null || return
    echo "  Killing PID=$pid  $(ps -o pid=,lstart=,comm= -p "$pid" 2>/dev/null | tr -s ' ' | sed 's/^ *//')"
    kill -TERM "$pid" 2>/dev/null || true
    killed_any=1
}
for pid in $LISTEN_PIDS; do kill_pid_safe "$pid"; done
sleep 1
for pid in $LISTEN_PIDS; do
    if kill -0 "$pid" 2>/dev/null; then
        echo "  PID $pid still alive, SIGKILL"
        kill -KILL "$pid" 2>/dev/null || true
    fi
done
# Also kill any python processes that have BACKEND_DIR / project path in their cmdline
if command -v pgrep >/dev/null 2>&1; then
    MATCH_PATHS=("$BACKEND_DIR" "$SCRIPT_DIR")
    for pat in "${MATCH_PATHS[@]}"; do
        [ -z "$pat" ] && continue
        while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            kill_pid_safe "$pid"
        done < <(pgrep -f "$pat" 2>/dev/null | sort -u)
    done
fi
if [ "$killed_any" = "0" ]; then
    echo "  Port $PORT is clean."
fi
echo ""

# ------------------------------------------------------------------
# [1/4] Virtual environment (explicit venv python, no source activate)
# ------------------------------------------------------------------
if [ ! -x "$VENV_PY" ]; then
    echo "[1/4] Creating Python virtual environment..."
    if [ -d "$BACKEND_DIR/venv" ]; then rm -rf "$BACKEND_DIR/venv"; fi
    PY3="$(command -v python3 || command -v python || true)"
    if [ -z "${PY3:-}" ]; then
        echo "[ERROR] python3 / python not found. Please install Python 3.10+." >&2
        exit 1
    fi
    cd "$BACKEND_DIR"
    "$PY3" -m venv venv || {
        echo "[ERROR] Failed to create venv." >&2
        exit 1
    }
    if [ ! -x "$VENV_PY" ]; then
        echo "[ERROR] venv python still missing after venv creation." >&2
        exit 1
    fi
    cd "$BACKEND_DIR"
else
    echo "[1/4] venv already exists."
    cd "$BACKEND_DIR"
fi
echo "      Using Python:"
"$VENV_PY" --version
"$VENV_PY" -c "import sys; print('        ' + sys.executable)"
echo ""

# ------------------------------------------------------------------
# [2/4] Dependencies (explicit venv python -m pip)
# ------------------------------------------------------------------
echo "[2/4] Installing / upgrading dependencies (venv pip)..."
"$VENV_PY" -m pip install --upgrade pip -q 2>&1 | tail -n 3 || true
"$VENV_PY" -m pip install -r requirements.txt -q 2>&1 | tail -n 10 || {
    echo "[ERROR] Failed to install dependencies." >&2
    exit 1
}
echo ""

# ------------------------------------------------------------------
# [3/4] Background helper: open browser once /api/health returns 200.
# ------------------------------------------------------------------
echo "[3/4] Starting browser warmup helper (background) + uvicorn..."
WARMUP_PY="$BACKEND_DIR/_warmup_helper.py"
cat > "$WARMUP_PY" <<'PY'
import sys, time, webbrowser, urllib.request
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
url = sys.argv[2] if len(sys.argv) > 2 else f"http://localhost:{port}"
health = f"http://localhost:{port}/api/health"
deadline = time.time() + 30
while time.time() < deadline:
    try:
        with urllib.request.urlopen(health, timeout=3) as r:
            if 200 <= r.status < 300:
                webbrowser.open(url)
                sys.exit(0)
    except Exception:
        time.sleep(0.4)
        continue
    time.sleep(0.4)
PY
nohup "$VENV_PY" "$WARMUP_PY" "$PORT" "http://localhost:$PORT" >/dev/null 2>&1 &
WARMUP_PID=$!

echo ""
echo "========================================"
echo "  Server starting..."
echo "  URL      : http://localhost:$PORT"
echo "  API      : http://localhost:$PORT/api/prices"
echo "  Health   : http://localhost:$PORT/api/health"
echo "  (Ctrl+C to stop)"
echo "========================================"
echo ""

cleanup() {
    echo ""
    echo "Stopping uvicorn + port $PORT listeners..."
    kill -TERM "$WARMUP_PID" 2>/dev/null || true
    if command -v lsof >/dev/null 2>&1; then
        lsof -t -iTCP:$PORT -sTCP:LISTEN -n -P 2>/dev/null | sort -u | while read -r p; do
            kill -TERM "$p" 2>/dev/null || true
        done
        sleep 1
        lsof -t -iTCP:$PORT -sTCP:LISTEN -n -P 2>/dev/null | sort -u | while read -r p; do
            kill -KILL "$p" 2>/dev/null || true
        done
    fi
    rm -f "$WARMUP_PY"
    echo "Stopped."
}
trap cleanup INT TERM EXIT

# ------------------------------------------------------------------
# [4/4] Foreground uvicorn (blocks until Ctrl+C)
# ------------------------------------------------------------------
"$VENV_PY" -m uvicorn main:app --host 0.0.0.0 --port "$PORT" --reload
