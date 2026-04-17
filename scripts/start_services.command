#!/usr/bin/env bash
# Zaban — launch background services on macOS.
#
# Mirrors start_services.bat: starts Ollama + Moonshine STT (Whisper fallback) +
# Kokoro TTS. Double-clickable in Finder thanks to the .command extension.
# Leaves each sidecar in its own Terminal tab so you can see the logs.
set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
VENV_DIR="$ROOT_DIR/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"

echo "============================================"
echo "   Zaban — Starting Background Services"
echo "============================================"
echo

if [[ ! -x "$VENV_PYTHON" ]]; then
    echo "  [X] Virtual environment not found at .venv/"
    echo "      Run scripts/setup_macos.sh first."
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
fi
echo "  Using virtual environment: $VENV_DIR"
echo

# Launch a command in a new Terminal window so its logs are visible and it
# keeps running after this script exits. Uses AppleScript since macOS has
# no direct equivalent of `start "title" /min cmd /c ...`.
launch_in_terminal() {
    local title="$1"
    local cmd="$2"
    osascript <<EOF >/dev/null
tell application "Terminal"
    do script "echo -n -e '\\033]0;${title}\\007'; ${cmd}"
end tell
EOF
}

# ---- 1/3: Ollama ----
echo "[1/3] Starting Ollama..."
if command -v ollama >/dev/null 2>&1; then
    if pgrep -x ollama >/dev/null; then
        echo "  [OK] Ollama already running"
    else
        launch_in_terminal "Ollama" "ollama serve"
        echo "  [OK] Ollama started on port 11434"
        sleep 2
    fi
else
    echo "  [SKIP] Ollama not installed — install via: brew install ollama"
fi

# ---- 2/3: Speech-to-Text (Moonshine preferred, Whisper fallback) ----
echo
echo "[2/3] Starting Speech-to-Text server..."
MOONSHINE_SCRIPT="$SCRIPT_DIR/moonshine_server.py"
WHISPER_SCRIPT="$SCRIPT_DIR/whisper_server.py"
if "$VENV_PYTHON" -c "from moonshine_onnx import MoonshineOnnxModel" >/dev/null 2>&1; then
    launch_in_terminal "Moonshine STT" \
        "'$VENV_PYTHON' '$MOONSHINE_SCRIPT' --port 8000 --model moonshine/base"
    echo "  [OK] Moonshine STT started on port 8000 (model: moonshine/base)"
elif "$VENV_PYTHON" -c "from faster_whisper import WhisperModel" >/dev/null 2>&1; then
    launch_in_terminal "Whisper STT" \
        "'$VENV_PYTHON' '$WHISPER_SCRIPT' --port 8000 --model small"
    echo "  [OK] Whisper STT started on port 8000 (Moonshine fallback)"
else
    echo "  [SKIP] No STT backend in .venv"
    echo "         Run: .venv/bin/pip install useful-moonshine-onnx"
    echo "         Or:  .venv/bin/pip install faster-whisper"
fi

# ---- 3/3: Kokoro TTS ----
echo
echo "[3/3] Starting Text-to-Speech server..."
TTS_SCRIPT="$SCRIPT_DIR/kokoro_tts_server.py"
if "$VENV_PYTHON" -c "from kokoro import KPipeline" >/dev/null 2>&1; then
    launch_in_terminal "Kokoro TTS" \
        "'$VENV_PYTHON' '$TTS_SCRIPT' --port 8880"
    echo "  [OK] Kokoro TTS started on port 8880"
else
    echo "  [SKIP] Kokoro not installed in .venv"
    echo "         Run: .venv/bin/pip install kokoro soundfile numpy"
fi

echo
echo "============================================"
echo "  Services started!"
echo "============================================"
echo
echo "  Ollama LLM:    http://localhost:11434"
echo "  Moonshine STT: http://localhost:8000"
echo "  Kokoro TTS:    http://localhost:8880"
echo
echo "  Now run:  flutter run -d macos"
echo
read -n 1 -s -r -p "Press any key to close this window (services keep running)..."
echo
