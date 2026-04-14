# CLAUDE.md — project context for Claude Code

This file is auto-loaded into every Claude Code session in this repo. Keep it focused: explain things that aren't obvious from the code, not things a grep can find.

---

## What this project is

**Zaban** — an offline desktop English tutor for Persian (Farsi) speakers. Flutter Desktop (Windows), with local LLMs (Ollama / llama.cpp / flutter_gemma), Whisper STT, and Kokoro TTS. Nothing calls out to any cloud — all inference runs on the user's machine.

Target user profile: adult Persian speaker, CEFR A1–C1, laptop-class hardware (8–16 GB RAM, often weak or no GPU).

---

## Code layout

```
lib/
  main.dart                  entry point; wires Providers; warms Kokoro
  config/                    theme
  models/                    pure data classes (Message, Conversation, CEFRLevel, Scenario, Flashcard, UserProfile, HardwareTier, HFModel, …)
  providers/                 ChangeNotifiers (ChatProvider, SettingsProvider, SRSProvider, LessonProvider)
  services/                  all side effects live here
    llm_backend.dart         abstract LLMBackend interface + BackendStatus
    llm_backend_*.dart       concrete backends: ollama, direct (llama_cpp_dart FFI), gemma (flutter_gemma)
    llm_backend_factory.dart picks backend from UserProfile
    llm_service.dart         high-level CEFR-adaptive chat API (system prompts, context window, temperature per level)
    sentence_tts_player.dart  streaming sentence-chunked TTS + gap-free playback queue
    tts_service.dart         HTTP client for Kokoro/Piper
    whisper_transcription_service.dart  HTTP client for Whisper server
    audio_service.dart       microphone recording (`record` package)
    database_service.dart    SQLite (sqflite_ffi), schema migrations, WAL mode
    cefr_service.dart        CEFR-J word list lookup, token-miss-rate
    srs_service.dart         SM-2 spaced repetition
    translation_service.dart LLM-backed English→Persian lookup with caching
    hardware_detection_service.dart  auto-detects HardwareTier
    huggingface_service.dart  in-app model browsing + download
    model_download_manager.dart  download progress state
  screens/                   one folder per tab; widgets/ subdir for tab-local widgets
  widgets/                   cross-tab shared widgets (BilingualText, CEFRBadge, ModelStatusIndicator)
  utils/                     persian_utils (digit/direction helpers), phoneme_mappings

scripts/
  whisper_server.py          faster-whisper HTTP server on :9000
  kokoro_tts_server.py       Kokoro HTTP server on :8880 (warmed on startup)
  start_services.bat         launches all 3 sidecars (Ollama + Whisper + Kokoro)
  fetch_llama_dlls.bat       downloads prebuilt llama.cpp DLLs from GitHub Release

windows/                     Flutter Windows runner (stock) + CMake customizations
  CMakeLists.txt             note: copies bin/windows/llama/*.dll into the build output
bin/windows/llama/           prebuilt llama.cpp DLLs — NOT in git, fetched via script
```

---

## Architecture, the short version

**Three-layer LLM stack.** UI providers never talk to HTTP or FFI directly. They go through `LLMService`, which holds an `LLMBackend`. Backends are swappable at runtime. This is what makes the "auto-fallback to Ollama when Direct GGUF runs out of RAM" feature possible — swapping the backend doesn't restart the app.

**SettingsProvider owns LLMService.** Don't construct an `LLMService` anywhere else. The `ChangeNotifierProxyProvider` in `main.dart` hands it to other providers.

**Python sidecars, not FFI.** STT and TTS run as separate HTTP servers managed by `start_services.bat`. This keeps the Flutter app small and lets users swap speech models without rebuilding. Only llama.cpp is loaded in-process (via llama_cpp_dart FFI).

**Streaming everywhere.** LLM tokens stream token-by-token. TTS is sentence-chunked and pipelined through `SentenceTtsPlayer` — first audio plays ~1s after sending, while the LLM is still generating later sentences.

---

## Backends — which does what

| Backend | Class | Transport | When to use |
|---|---|---|---|
| `ollama` | `OllamaBackend` | HTTP `:11434` | Default, most reliable. Easy model install via `ollama pull`. |
| `directFfi` | `DirectLlamaBackend` | llama_cpp_dart FFI + Windows DLLs | ~20% faster than Ollama but fragile (see Windows DLL gotcha below) |
| `gemma` | `GemmaBackend` | flutter_gemma plugin + MediaPipe LiteRT | Only works if your GPU supports LiteRT (many don't) |

`LLMBackendFactory.createFromProfile()` picks one. `SettingsProvider.initialize()` always validates and will fall back to Ollama silently if the user's chosen backend fails.

---

## Non-obvious gotchas

### Windows llama.cpp DLL loading
**Don't change `DirectLlamaBackend.initialize()` without reading this.** On Windows, `llama_cpp_dart` loads ONE library via `DynamicLibrary.open()` but needs symbols from llama.dll + ggml.dll + ggml-base.dll + ggml-cpu.dll. The fix: pre-load all DLLs into the process, then set `Llama.libraryPath = null` so the package uses `DynamicLibrary.process()` which searches all loaded modules. This also makes it work across Dart isolates (since native libs are process-wide, not isolate-local).

The prebuilt DLLs on the GitHub Release are built with `GGML_BACKEND_DL=OFF` — ggml backends are statically linked into each DLL. **Upstream llama.cpp Windows releases are incompatible** (they split `ggml_backend_load_all` into `ggml.dll`). Always use the project's custom build, not upstream binaries.

### flutter_gemma path normalization
flutter_gemma's internal `_extractFilename` uses `path.split('/')`, which returns the whole string on Windows backslash paths → "Active model is no longer installed" error. Always normalize: `modelPath.replaceAll('\\', '/')` before calling `installModel().fromFile()`. See `GemmaBackend.initialize()`.

### flutter_gemma GPU → CPU fallback
LiteRT's GPU backend fails on many consumer GPUs (MX150 tested: broken). `GemmaBackend` has a `_gpuFailed` flag and retries with `PreferredBackend.cpu` on failure. If you add code paths that call `getActiveModel(preferredBackend: …)`, respect the flag.

### SQLite migrations and FK cascade
The `messages` table has `ON DELETE CASCADE` in the schema, but SQLite **cannot retrofit FK constraints via `ALTER TABLE`**. So existing DBs created before the CASCADE was added still don't cascade. `DatabaseService.deleteConversation` deletes messages explicitly in a transaction to work on both old and new DBs. Don't rely on CASCADE.

### TTS pipeline ordering
`SentenceTtsPlayer` uses a generation counter to invalidate stale work. When switching conversations mid-stream, `cancel()` increments the counter so any still-running synths are discarded when they complete. Don't change to a boolean — you need the counter for this to be correct.

### Ollama keep_alive vs RAM pressure
When switching backends Ollama→Direct GGUF, the app POSTs `keep_alive:0` to Ollama's `/api/generate` to unload the model and free RAM. Without this, on 16 GB systems the new backend's model load fails. See `SettingsProvider._unloadOllamaModel()`.

---

## Pedagogy — why the system prompt looks the way it does

`LLMService.buildConversationPrompt()` is the core pedagogical artifact. It encodes:

1. **CEFR-locked vocabulary.** A1 = top 500 words, max 8-word sentences, present simple + present continuous + "can" only. This is a hard constraint on the model, not a suggestion.
2. **Persian L1 transfer errors.** The prompt lists the specific errors Persian speakers make (missing articles, `afraid from X`, SOV word order, missing third-person `-s`, question-without-inversion) so the model recognizes and gently recasts them.
3. **Gentle recasting, not lecturing.** Corrections happen naturally in-conversation ("Oh, you *went* yesterday?") rather than as grammar mini-lectures.
4. **Always end with a question.** This was added after user feedback — the tutor must end every response with a follow-up question to keep the conversation going. Changing this will silently break conversation flow.
5. **Temperature scales with level.** A1 = 0.4 (deterministic, safe vocabulary), C1 = 0.8. See `LLMService.temperatureForLevel`.

Token-miss-rate (TMR) is tracked as a quality gate: `CEFRService.tokenMissRate` counts how many content words fall above the student's level. If TMR > 0.2, the response is logged as above-target. This is observability only — we don't reject responses (yet).

---

## Running the app

```bash
# First time only
setup.bat                       # creates .venv, installs Python deps, fetches DLLs
ollama pull gemma3:1b           # pull a small LLM

# Every session
scripts\start_services.bat      # starts Whisper + Kokoro (+ Ollama if needed)
flutter run -d windows          # run the app
```

Tests: `flutter test` (sparse — mostly smoke). Static: `flutter analyze` (keep it clean). Build release: `flutter build windows --release`.

---

## Conventions

- **No new top-level HTTP clients.** Services own their own `http.Client` and dispose it.
- **Use `debugPrint` for logs.** No `print()` — it leaks into release builds.
- **Providers are UI-facing.** Don't stick business logic in ChangeNotifier methods; put it in `services/` and have the provider call it.
- **Bilingual UI.** Any user-facing English string also has a Persian gloss nearby (`BilingualText` widget handles the common case).
- **Error messages include Persian.** `ChatProvider._getErrorMessage` is the template: English explanation + `(توضیح فارسی)`.
- **RTL for Persian.** Wrap Persian text in `Directionality(textDirection: TextDirection.rtl, …)` when it's not inside a `BilingualText`.
- **Streaming is the default.** New LLM calls should use `chatStream()` not `chat()`. The non-streaming variant exists for one-shot JSON extraction (corrections, translations).

---

## What not to do

- Don't add a `dart:io` `Process.run('powershell', …)` for audio. Use `SentenceTtsPlayer` / the `audioplayers` package.
- Don't commit files from `bin/windows/llama/`, `_llama_build/`, `build/`, `.dart_tool/`, or `.venv/`. The `.gitignore` excludes them; the fetch script provides them.
- Don't commit GGUF / LiteRT / safetensors model files. Ever.
- Don't write directly to SQLite from outside `DatabaseService`. Schema version is tracked and migrations run on open.
- Don't assume the LLM backend type at the call site. Go through `LLMService`. If you need to know (e.g. UI), read `SettingsProvider.profile.backendType`.
- Don't swap `just_audio` back in — it doesn't have first-class Windows support. `audioplayers` uses miniaudio and works out of the box.

---

## When something's broken

| Symptom | First place to look |
|---|---|
| "Connection refused" on LLM | Is Ollama running? `ollama list` — if empty, `ollama pull gemma3:1b` |
| TTS silent | Is Kokoro running? Watch the `start_services.bat` console for `[OK] Pipeline warm.` |
| Voice input transcribes nothing | Whisper on `:9000`. Check console. Check mic is default recording device. |
| "llama.dll not found" | `scripts\fetch_llama_dlls.bat` |
| Gemma says "Active model is no longer installed" | Path normalization bug — re-verify `.replaceAll('\\', '/')` is in place |
| Status bar orange | Primary backend failed → on Ollama fallback. Hover/check `_backendStatus.error` |
| App feels slow to first voice | Kokoro cold-start. Confirm the server printed `[OK] Pipeline warm.` at startup |
| Chat response doesn't ask a follow-up | `buildConversationPrompt` regression — check the "CRITICAL: ALWAYS end" line is still there |

---

## Adding a feature — decision tree

1. Is this a new LLM backend? Implement `LLMBackend`, add to `BackendType` enum, handle in `LLMBackendFactory`, add a tab to `SettingsScreen`.
2. Is this a new tab? Add to `HomeScreen`'s tab list, create a folder under `screens/`, and keep tab-local widgets in `screens/<tab>/widgets/`.
3. Is this a new lesson scenario? Add to `LessonData` in `models/lesson.dart`.
4. Is this a data schema change? Bump `_dbVersion` in `DatabaseService`, add an `onUpgrade` case. Test against an existing DB — don't just nuke `zaban.db` during development.
5. Is this a new speech model? Most likely swap the backend server in `scripts/` without touching Dart. The `TTSService` / `WhisperTranscriptionService` HTTP contracts are stable.
