@echo off
:: Downloads prebuilt llama.cpp DLLs for the Direct GGUF backend.
:: These are custom-built from llama.cpp source with GGML_BACKEND_DL=OFF
:: so all ggml symbols are statically linked into each DLL (required for
:: llama_cpp_dart's single-library loader on Windows).
::
:: Hosted as release assets on the project repo.

setlocal enabledelayedexpansion

set "REPO=alij1991/zaban"
set "TAG=v0.1.0-binaries"
set "DEST=%~dp0..\bin\windows\llama"
set "ARCHIVE=%TEMP%\llama_dlls.zip"

echo ============================================
echo   Downloading llama.cpp DLLs
echo ============================================
echo.
echo Source: https://github.com/%REPO%/releases/tag/%TAG%
echo Target: %DEST%
echo.

if not exist "%DEST%" mkdir "%DEST%"

:: Prefer gh if available (handles auth, rate limits)
gh --version >nul 2>&1
if %errorlevel% equ 0 (
    echo Using gh CLI...
    gh release download %TAG% --repo %REPO% --pattern "llama_dlls_windows.zip" --output "%ARCHIVE%" --clobber
    if !errorlevel! neq 0 goto :curl_fallback
    goto :extract
)

:curl_fallback
echo Using curl...
curl -L -o "%ARCHIVE%" "https://github.com/%REPO%/releases/download/%TAG%/llama_dlls_windows.zip"
if %errorlevel% neq 0 (
    echo.
    echo [X] Download failed. Check your internet connection.
    echo     You can manually download from:
    echo     https://github.com/%REPO%/releases/tag/%TAG%
    echo     Extract the zip into: %DEST%
    exit /b 1
)

:extract
echo.
echo Extracting...
powershell -NoProfile -Command "Expand-Archive -Path '%ARCHIVE%' -DestinationPath '%DEST%' -Force"
if %errorlevel% neq 0 (
    echo [X] Extraction failed.
    exit /b 1
)

del "%ARCHIVE%" >nul 2>&1

echo.
echo [OK] DLLs installed to %DEST%
dir /b "%DEST%\*.dll" | findstr /c:"llama.dll" >nul
if %errorlevel% equ 0 (
    echo [OK] llama.dll present
) else (
    echo [!] Warning: llama.dll not found after extraction.
)

endlocal
