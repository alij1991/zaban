# Zaban Setup Guide

## Quick Start — Windows

```batch
:: 1. Install dependencies (creates .venv/ with Python packages + fetches llama DLLs)
setup.bat

:: 2. Start background services (uses .venv/ automatically)
scripts\start_services.bat

:: 3. Run the app
flutter run -d windows
```

## Quick Start — macOS

```bash
# 1. First-time setup (creates .venv/, installs Python deps)
bash scripts/setup_macos.sh

# 2. Pull an LLM (macOS uses the Ollama backend — see note below)
brew install ollama
ollama pull qwen3:1.7b

# 3. Start background services (opens Ollama + Moonshine + Kokoro in Terminal tabs)
scripts/start_services.command

# 4. Run the app
flutter run -d macos
```

> **macOS backend note.** Only the **Ollama** backend is supported on macOS right now. The Direct GGUF (llama.cpp FFI) backend ships prebuilt Windows DLLs only; the Gemma (flutter_gemma / LiteRT) backend is untested on macOS. Pick "Ollama" under Settings → AI Model.

All Python packages (Moonshine/Whisper STT, Kokoro TTS) install into a local `.venv/` virtual environment — not your global Python. The launcher scripts run everything from the venv automatically.

## Prerequisites

| Tool | Windows | macOS | Purpose |
|------|---------|-------|---------|
| Flutter 3.38+ | Yes | Yes | App framework |
| Visual Studio 2022 | Yes | — | C++ compiler for Windows build |
| Xcode 15+ | — | Yes | macOS build toolchain |
| Python 3.10+ | Yes | Yes | STT and TTS servers |
| Ollama | Optional | **Required** | Local LLM inference |
| NVIDIA GPU + CUDA | Optional | — | GPU acceleration for Windows Direct GGUF |

## LLM Backend Setup

### Option A: Ollama (default on macOS, easiest on Windows)
```bash
# Windows: install from https://ollama.com
# macOS:   brew install ollama

ollama serve
ollama pull qwen3:1.7b    # 4 GB RAM machines
ollama pull qwen3:4b      # 8+ GB RAM machines (recommended)
ollama pull qwen3:8b      # 16+ GB RAM machines
```

The app auto-picks a model based on system RAM via `LlmModelCatalog.pickForRam`. You can override it under Settings → AI Model.

### Option B: Direct GGUF — Windows only
1. Download a GGUF model (or use the in-app HuggingFace downloader).
2. Settings → AI Model → Direct GGUF → Browse to the `.gguf` file.

Recommended models (real Ollama-registry tags, verified):
- **Qwen3-8B Q4_K_M** (~5 GB) — Best for Persian + English bilingual
- **Qwen3-4B Q4_K_M** (~2.5 GB) — Lightweight, still bilingual
- **Gemma 3 1B Q4_K_M** (~0.8 GB) — Smallest, good for CPU-only / sub-4 GB RAM

### Option C: Gemma LiteRT — Windows (untested on macOS)
1. Download a `.litertlm` model file.
2. Settings → AI Model → Gemma → Browse to the file.

## Speech-to-Text Setup

Primary engine: **Moonshine v2** — English-only, ~100ms CPU latency, no GPU needed.
The setup scripts install it into `.venv/` automatically. Manual install:

```bash
# Windows
.venv\Scripts\pip install useful-moonshine-onnx
.venv\Scripts\python scripts\moonshine_server.py --port 8000

# macOS
.venv/bin/pip install useful-moonshine-onnx
.venv/bin/python scripts/moonshine_server.py --port 8000
```

Fallback engine: **faster-whisper** (same port, same API). The launcher
automatically uses it if `moonshine-onnx` is unavailable:

```bash
# Windows
.venv\Scripts\pip install faster-whisper

# macOS
.venv/bin/pip install faster-whisper
```

## Text-to-Speech Setup

```bash
# Windows
.venv\Scripts\pip install kokoro soundfile numpy
.venv\Scripts\python scripts\kokoro_tts_server.py --port 8880

# macOS
.venv/bin/pip install kokoro soundfile numpy
.venv/bin/python scripts/kokoro_tts_server.py --port 8880
```

Runs on port 8880. The app auto-detects when available.

## GPU Acceleration

- **Windows + NVIDIA**: install CUDA Toolkit 12.x from https://developer.nvidia.com/cuda-toolkit. The app auto-detects VRAM and picks a matching model.
- **macOS / Apple Silicon**: GPU-accelerated LLM inference is delegated to Ollama (which uses Metal automatically). Zaban itself doesn't need any extra setup.

## Service Ports

| Service | Port | URL |
|---------|------|-----|
| Ollama | 11434 | http://localhost:11434 |
| Moonshine / Whisper STT | 8000 | http://localhost:8000 |
| Kokoro TTS | 8880 | http://localhost:8880 |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Ollama not running" | `ollama serve` (Windows) or `brew services start ollama` (macOS) |
| Voice input not working | Run `scripts\start_services.bat` (Win) or `scripts/start_services.command` (mac) |
| macOS: mic permission not prompted | Check `System Settings → Privacy → Microphone`; delete `~/Library/Application Support/Zaban` and re-launch |
| macOS: "Direct GGUF is Windows-only" in UI | Expected — switch Settings → Backend → Ollama |
| No audio playback | Confirm Kokoro is running on port 8880 |
| Model too slow | Use a smaller model or check hardware detection in Settings |
| Build fails | `flutter clean && flutter pub get` |
