#!/usr/bin/env bash
# Zaban — first-time macOS setup.
#
# Mirrors setup.bat for Windows, minus the llama.cpp DLL fetch (macOS
# currently runs with the Ollama backend only — see CLAUDE.md).
set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
VENV_DIR="$ROOT_DIR/.venv"

echo "============================================"
echo "   Zaban — AI English Tutor Setup (macOS)"
echo "============================================"
echo

# ---- 1/5: Python ----
echo "[1/5] Checking Python..."
if ! command -v python3 >/dev/null 2>&1; then
    echo "  [X] python3 not found. Install via: brew install python"
    exit 1
fi
PY_VERSION="$(python3 --version 2>&1)"
echo "  [OK] $PY_VERSION"

# ---- 2/5: venv ----
echo
echo "[2/5] Creating virtual environment..."
if [[ -x "$VENV_DIR/bin/python" ]]; then
    echo "  [OK] Virtual environment already exists at .venv/"
else
    python3 -m venv "$VENV_DIR"
    echo "  [OK] Created .venv/"
fi

# ---- 3/5: Python packages ----
echo
echo "[3/5] Installing Python packages into .venv/..."
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null
"$VENV_DIR/bin/pip" install -r "$ROOT_DIR/requirements.txt" \
    | grep -Ei "successfully|already satisfied" || true
echo "  [OK] Python packages installed"

# ---- 4/5: Ollama ----
echo
echo "[4/5] Checking Ollama..."
if command -v ollama >/dev/null 2>&1; then
    echo "  [OK] $(ollama --version 2>&1)"
else
    echo "  [!] Ollama not found. Install with: brew install ollama"
    echo "      Or download from https://ollama.com"
fi

# ---- 5/5: Flutter ----
echo
echo "[5/5] Checking Flutter..."
if command -v flutter >/dev/null 2>&1; then
    echo "  [OK] $(flutter --version 2>&1 | head -1)"
else
    echo "  [X] Flutter not found. Install from https://flutter.dev"
fi

echo
echo "============================================"
echo "   Setup complete!"
echo "============================================"
echo
echo "   Next steps:"
echo "   1. Pull a model:    ollama pull qwen3:1.7b"
echo "   2. Start services:  scripts/start_services.command"
echo "   3. Run the app:     flutter run -d macos"
echo
echo "   Note: the Direct GGUF and Gemma backends are Windows-only for now."
echo "   Use the Ollama backend in Settings on macOS."
echo
