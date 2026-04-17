@echo off
title Zaban - Service Launcher
echo ============================================
echo   Zaban - Starting Background Services
echo ============================================
echo.

set "VENV_DIR=%~dp0..\.venv"
set "VENV_PYTHON=%VENV_DIR%\Scripts\python.exe"
set "VENV_BIN=%VENV_DIR%\Scripts"

:: Verify venv exists
if not exist "%VENV_PYTHON%" (
    echo   [X] Virtual environment not found at .venv\
    echo       Run setup.bat first to create it.
    pause
    exit /b 1
)
echo   Using virtual environment: .venv\
echo.

:: ---- Start Ollama ----
echo [1/3] Starting Ollama...
ollama --version >nul 2>&1
if %errorlevel% equ 0 (
    tasklist /fi "imagename eq ollama.exe" 2>nul | find /i "ollama.exe" >nul
    if %errorlevel% neq 0 (
        start "Ollama" /min cmd /c "ollama serve"
        echo   [OK] Ollama started on port 11434
        timeout /t 2 /nobreak >nul
    ) else (
        echo   [OK] Ollama already running
    )
) else (
    echo   [SKIP] Ollama not installed
)

:: ---- Start Speech-to-Text (from venv) ----
:: Prefer Moonshine v2 (~10x lower CPU latency than Whisper small,
:: English-only — matches our Persian-speakers-learning-English use case).
:: Fall back to Whisper if moonshine-onnx isn't installed.
echo.
echo [2/3] Starting Speech-to-Text server...
set "MOONSHINE_SCRIPT=%~dp0moonshine_server.py"
set "WHISPER_SCRIPT=%~dp0whisper_server.py"
"%VENV_PYTHON%" -c "from moonshine_onnx import MoonshineOnnxModel" >nul 2>&1
if %errorlevel% equ 0 (
    start "Moonshine STT" /min cmd /c ""%VENV_PYTHON%" "%MOONSHINE_SCRIPT%" --port 8000 --model moonshine/base"
    echo   [OK] Moonshine STT started on port 8000 (model: moonshine/base)
) else (
    "%VENV_PYTHON%" -c "from faster_whisper import WhisperModel" >nul 2>&1
    if %errorlevel% equ 0 (
        start "Whisper STT" /min cmd /c ""%VENV_PYTHON%" "%WHISPER_SCRIPT%" --port 8000 --model small"
        echo   [OK] Whisper STT started on port 8000 (model: small, Moonshine fallback)
    ) else (
        echo   [SKIP] No STT backend installed in .venv
        echo          Run: .venv\Scripts\pip install useful-moonshine-onnx
        echo          Or fallback: .venv\Scripts\pip install faster-whisper
    )
)

:: ---- Start Kokoro TTS (from venv) ----
echo.
echo [3/3] Starting Text-to-Speech server...
set "TTS_SCRIPT=%~dp0kokoro_tts_server.py"
"%VENV_PYTHON%" -c "from kokoro import KPipeline" >nul 2>&1
if %errorlevel% equ 0 (
    start "Kokoro TTS" /min cmd /c ""%VENV_PYTHON%" "%TTS_SCRIPT%" --port 8880"
    echo   [OK] Kokoro TTS started on port 8880
) else (
    echo   [SKIP] Kokoro not installed in .venv
    echo          Run: .venv\Scripts\pip install kokoro soundfile numpy
)

echo.
echo ============================================
echo   Services started!
echo ============================================
echo.
echo   Ollama LLM:    http://localhost:11434
echo   Whisper STT:   http://localhost:8000
echo   Kokoro TTS:    http://localhost:8880
echo.
echo   Now run:  flutter run -d windows
echo.
echo   Press any key to close (services keep running)
pause >nul
