@echo off
title Zaban - Environment Setup
echo ============================================
echo   Zaban - AI English Tutor Setup
echo ============================================
echo.

set "VENV_DIR=%~dp0.venv"
set "VENV_PIP=%VENV_DIR%\Scripts\pip.exe"
set "VENV_PYTHON=%VENV_DIR%\Scripts\python.exe"

:: ---- Step 1: Check Python ----
echo [1/6] Checking Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [X] Python not found. Install from https://python.org
    echo       Make sure to check "Add to PATH" during installation.
    pause
    exit /b 1
)
for /f "tokens=2" %%i in ('python --version 2^>^&1') do echo   [OK] Python %%i found

:: ---- Step 2: Create virtual environment ----
echo.
echo [2/6] Creating virtual environment...
if exist "%VENV_DIR%\Scripts\activate.bat" (
    echo   [OK] Virtual environment already exists at .venv\
) else (
    echo   Creating .venv\ ...
    python -m venv "%VENV_DIR%"
    if %errorlevel% neq 0 (
        echo   [X] Failed to create virtual environment.
        echo       Try: python -m pip install --upgrade pip virtualenv
        pause
        exit /b 1
    )
    echo   [OK] Virtual environment created at .venv\
)

:: ---- Step 3: Install Python packages into venv ----
echo.
echo [3/6] Installing Python packages into .venv\ ...
echo   This may take a few minutes on first run...
"%VENV_PIP%" install -r "%~dp0requirements.txt" 2>&1 | findstr /i "Successfully\|already satisfied"
echo   [OK] Python packages installed into .venv\

:: ---- Step 4: Check Ollama ----
echo.
echo [4/6] Checking Ollama...
ollama --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [!] Ollama not found. Download from https://ollama.ai
    echo       Ollama is optional if using Direct GGUF or Gemma backend.
) else (
    for /f "tokens=*" %%i in ('ollama --version 2^>^&1') do echo   [OK] %%i
)

:: ---- Step 5: Create model directory ----
echo.
echo [5/6] Creating local directories...
if not exist "%APPDATA%\com.persiantutor\zaban\models" mkdir "%APPDATA%\com.persiantutor\zaban\models"
echo   [OK] Models directory: %APPDATA%\com.persiantutor\zaban\models

:: ---- Step 6: Check Flutter + GPU ----
echo.
echo [6/6] Checking build tools and GPU...
flutter --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [X] Flutter not found. Install from https://flutter.dev
) else (
    echo   [OK] Flutter found
)

nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits >nul 2>&1
if %errorlevel% neq 0 (
    echo   [!] No NVIDIA GPU detected. Models will run on CPU.
) else (
    for /f "tokens=1,2 delims=," %%a in ('nvidia-smi --query-gpu^=name^,memory.total --format^=csv^,noheader^,nounits 2^>nul') do (
        echo   [OK] GPU: %%a with %%b MB VRAM
    )
)

echo.
echo ============================================
echo   Setup complete!
echo ============================================
echo.
echo   Virtual environment: .venv\
echo   Activate manually:   .venv\Scripts\activate
echo.
echo   Next steps:
echo   1. Start services:  scripts\start_services.bat
echo   2. Run the app:     flutter run -d windows
echo.
pause
