# Zaban Setup Guide

## Quick Start

```batch
:: 1. Install dependencies (creates .venv/ with Python packages)
setup.bat

:: 2. Start background services (uses .venv/ automatically)
scripts\start_services.bat

:: 3. Run the app
flutter run -d windows
```

All Python packages (Moonshine/Whisper STT, Kokoro TTS) are installed into a local `.venv/` virtual environment — not your global Python. The `start_services.bat` script runs everything from the venv automatically.

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| Flutter 3.38+ | Yes | App framework |
| Visual Studio 2022 | Yes | C++ compiler for Windows build |
| Python 3.10+ | Yes | STT and TTS servers |
| Ollama | Optional | LLM inference (alternative to Direct GGUF) |
| NVIDIA GPU + CUDA | Optional | GPU acceleration for faster inference |

## LLM Backend Setup (choose one)

### Option A: Ollama (easiest)
```batch
:: Install from https://ollama.ai, then:
ollama serve
ollama pull qwen3:8b
```

### Option B: Direct GGUF (fastest, no server)
1. Download a GGUF model from HuggingFace (or use the in-app downloader)
2. In app Settings > AI Model > Direct GGUF > Browse to the .gguf file

Recommended models:
- **Qwen3-8B Q4_K_M** (~5 GB) — Best for Persian+English
- **Qwen3.5-4B Q4_K_M** (~2.5 GB) — Lightweight
- **Gemma 4 E4B Q4_K_M** (~3 GB) — Good all-rounder

### Option C: Gemma LiteRT (flutter_gemma)
1. Download a `.litertlm` model file
2. In app Settings > AI Model > Gemma > Browse to the file

Recommended: Gemma 4 E4B LiteRT-LM (~1.5 GB)

## Speech-to-Text Setup

Primary engine: **Moonshine v2** — English-only, ~100ms CPU latency, no GPU needed.
`setup.bat` installs it into `.venv/` for you. Manual install:

```batch
.venv\Scripts\pip install useful-moonshine-onnx
.venv\Scripts\python scripts\moonshine_server.py --port 8000
```

Fallback engine: **faster-whisper** (same port, same API). `start_services.bat`
automatically uses it if `moonshine-onnx` is unavailable:

```batch
.venv\Scripts\pip install faster-whisper
.venv\Scripts\python scripts\whisper_server.py --port 8000 --model small
```

Either runs on port 8000. The app auto-detects when available.

## Text-to-Speech Setup

```batch
pip install kokoro soundfile numpy
python -m kokoro.serve --port 8880
```
Runs on port 8880. The app auto-detects when available.

## GPU Acceleration

For NVIDIA GPUs, install CUDA Toolkit 12.x from https://developer.nvidia.com/cuda-toolkit

The app auto-detects your GPU and recommends the best model for your VRAM.

## Service Ports

| Service | Port | URL |
|---------|------|-----|
| Ollama | 11434 | http://localhost:11434 |
| Moonshine/Whisper STT | 8000 | http://localhost:8000 |
| Kokoro TTS | 8880 | http://localhost:8880 |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Ollama not running" | Run `ollama serve` |
| Voice input not working | Run `scripts\start_services.bat` or `.venv\Scripts\python scripts\moonshine_server.py` on port 8000 |
| No audio playback | Run `python -m kokoro.serve --port 8880` |
| Model too slow | Use smaller model or check GPU detection in Settings |
| Build fails | Run `flutter clean && flutter pub get` |
