# Zaban — Offline AI English Tutor for Persian Speakers

A Flutter Desktop app that combines a local LLM, Whisper speech-to-text, and Kokoro text-to-speech into a CEFR-adaptive English tutor designed around the phonological and grammatical challenges Persian speakers actually face.

Everything runs on your own machine. No cloud, no subscription, no data leaving the laptop.

زبان — معلم خصوصی انگلیسی آفلاین برای فارسی‌زبانان، اجرا شده کاملاً روی لپ‌تاپ شما.

---

## Features

- **Conversational tutor** — streaming chat with an LLM tuned to your CEFR level (A1–C2). Vocabulary and sentence length adapt automatically. The tutor always ends on a follow-up question to keep you talking.
- **Scenario lessons** — guided role-plays (airport check-in, doctor's visit, job interview, etc.) with progress tracking.
- **Voice input** — hold the mic, speak English, Whisper transcribes and the tutor responds.
- **Auto text-to-speech** — every AI response plays aloud in a natural voice (Kokoro). Tap the speaker icon to replay.
- **Pronunciation practice** — targets the 7 phonological challenges specific to Persian L1 speakers: `/w/` vs `/v/`, `/θ/` and `/ð/`, initial consonant clusters (`/sp-/`, `/st-/`), vowel length, word stress, `/æ/` vs `/ɑ/`, and final devoicing. Records your speech, compares against target, shows accuracy %.
- **Error correction** — tap the spell-check button to get grammar corrections with Persian explanations, focused on Persian L1 transfer errors (missing articles, wrong prepositions, SOV word order, third-person `-s`).
- **Spaced repetition flashcards** — SM-2 algorithm. New vocabulary introduced by the tutor is automatically saved as flashcards.
- **Bilingual UI** — English primary, Persian translations for everything. On-demand translation of any message.
- **Conversation history** — browse past sessions, swipe-left or tap trash icon to delete.
- **Multi-backend LLM** — choose Ollama (simplest), direct llama.cpp FFI (~20% faster, no server), or flutter_gemma (LiteRT). Auto-falls-back to Ollama if the primary backend fails.

---

## Requirements

- **OS**: Windows 10/11 x64 (macOS/Linux not yet tested — PRs welcome)
- **RAM**: 8 GB minimum, 16 GB recommended
- **GPU**: optional. Any NVIDIA GPU helps; integrated Intel works via CPU fallback
- **Disk**: ~5 GB (app + models)

You will also need:
- **[Flutter](https://flutter.dev)** 3.24+
- **[Python](https://python.org)** 3.10+ (for Whisper/Kokoro servers)
- **[Ollama](https://ollama.ai)** (recommended — simplest LLM backend)
- **Visual Studio 2022** with "Desktop development with C++" workload (for Flutter Windows builds)

---

## Quick start

```bash
# 1. Clone
git clone https://github.com/alij1991/zaban.git
cd zaban

# 2. One-shot setup: creates Python venv, installs deps, downloads llama.cpp DLLs
setup.bat

# 3. Pull a small LLM through Ollama
ollama pull gemma3:1b

# 4. Start the background services (Whisper STT + Kokoro TTS + Ollama)
scripts\start_services.bat

# 5. In another terminal, run the app
flutter run -d windows
```

On first launch the app auto-detects your hardware (CPU, RAM, VRAM) and recommends a model. You can change everything in Settings.

---

## What model should I pull?

| Your RAM + VRAM | Recommended Ollama model | Quality |
|---|---|---|
| 8 GB RAM, no GPU | `llama3.2:1b` or `gemma3:1b` | OK for A1–A2 |
| 16 GB RAM, 2 GB GPU | `gemma3:1b` + `gemma3:4b` | Great for A1–B1 |
| 16 GB RAM, 6+ GB GPU | `gemma3:4b` or `qwen3:8b` | Great for A2–C1 |
| 32 GB RAM, 12+ GB GPU | `qwen3:14b` or `gemma3:12b` | Excellent for all levels |

`gemma3:1b` is the safest default — it runs on nearly anything and the tutor quality is still good. Upgrade when you have headroom.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Flutter UI (lib/screens)                       │
│  Chat · Lessons · Pronunciation · Vocabulary    │
└────────────────┬────────────────────────────────┘
                 │
    ┌────────────┴────────────┬──────────────┐
    │                         │              │
┌───▼────────┐   ┌────────────▼──────┐  ┌────▼──────┐
│ ChatProv.  │   │ LLMService        │  │ SRSService│
│ LessonProv.│   │ (CEFR prompts,    │  │ (SM-2)    │
│ SettingsP. │   │  context window)  │  │           │
└───┬────────┘   └────────────┬──────┘  └───┬───────┘
    │                         │             │
    │             ┌───────────┴────┐        │
    │             │ LLMBackend     │        │
    │             │ (interface)    │        │
    │             └┬──────┬──────┬─┘        │
    │              │      │      │          │
    │     ┌────────▼┐ ┌───▼────┐ ┌▼───────┐ │
    │     │Ollama   │ │Direct  │ │flutter_│ │
    │     │HTTP     │ │llama   │ │gemma   │ │
    │     │         │ │FFI     │ │LiteRT  │ │
    │     └─────────┘ └────────┘ └────────┘ │
    │                                        │
    └──►┌─────────────────────────┐  ◄──────┘
        │ SQLite (sqflite_ffi)    │
        │  · conversations        │
        │  · messages             │
        │  · vocabulary / cards   │
        │  · user_profile         │
        └─────────────────────────┘

       Python subprocess servers (managed by start_services.bat):
       · Whisper STT on :9000    (scripts/whisper_server.py)
       · Kokoro TTS on :8880     (scripts/kokoro_tts_server.py)
       · Ollama     on :11434    (system service)
```

### Key design choices

- **LLMBackend abstraction** — the app is decoupled from any specific inference engine. Switching from Ollama to Direct GGUF at runtime doesn't restart the app.
- **Auto-fallback** — if your chosen backend fails to load (e.g. out of VRAM), the app silently falls back to Ollama with the smallest installed model and shows an orange warning in the status bar.
- **CEFR-locked prompts** — the system prompt enforces vocabulary constraints at A1/A2 (top 500/2000 words, sentence length caps, limited tenses). Temperature is also level-scaled.
- **Python sidecars, not bundled** — Whisper and Kokoro run as separate HTTP servers managed by a batch script. Keeps the Flutter app small; lets you swap models without recompiling.

---

## Using the app

### Chat tab
- Type or hold the 🎤 button to speak. Press Enter to send (Shift+Enter for newline).
- The AI's reply streams in and auto-plays through TTS.
- Tap 🔊 on any bubble to replay. Tap ✓ to get grammar corrections. Tap 🌐 to see a Persian translation.
- "Back" arrow returns to the history list. Swipe left on any past conversation to delete it.

### Lessons tab
Pick a scenario. The tutor role-plays it in character (cashier, doctor, taxi driver, etc.). Scenarios are filtered by CEFR level and topic. Tapping one auto-navigates to the Chat tab and starts the conversation.

### Pronunciation tab
Three sub-tabs:
- **Practice** — read a target sentence aloud, get an accuracy score
- **Minimal pairs** — tap pairs like "wet / vet" or "thin / sin" to hear the difference
- **Challenges** — focused drills on the 7 Persian-specific phonological targets

### Vocabulary tab
Review flashcards due today. Rate each (Again / Hard / Good / Easy) and SM-2 schedules the next review. New cards are auto-created from conversation whenever the tutor introduces a word with a Persian translation in parentheses.

### Settings tab
- **Backend** — Ollama / Direct GGUF / flutter_gemma. Each has its own model path.
- **CEFR level** — pick your current level (or change it as you progress)
- **Model download** — browse HuggingFace and download GGUF/LiteRT models directly into the app's model folder
- **Hardware** — re-run hardware detection, set VRAM/RAM hints manually
- **GPU layers** — advanced tuning for Direct GGUF

---

## Troubleshooting

**"Could not connect to the AI backend"**
- Is Ollama running? `ollama serve` or check `http://localhost:11434` in a browser.
- Is the selected model pulled? `ollama list` — if empty, run `ollama pull gemma3:1b`.

**TTS doesn't play (silent responses)**
- Check `scripts\start_services.bat` is still running.
- The Kokoro server logs to the console — look for errors on port 8880.
- First synthesis after cold-start can take 5–10 seconds.

**Voice input transcribes nothing**
- Whisper server on port 9000 — make sure the batch script started it.
- Check your microphone is selected as the Windows default recording device.

**Direct GGUF backend shows "llama.dll not found"**
- Run `scripts\fetch_llama_dlls.bat` to download the prebuilt DLLs.
- Or manually download from [Releases](https://github.com/alij1991/zaban/releases) and extract into `bin/windows/llama/`.

**App uses Ollama even though I selected Direct GGUF**
- You probably don't have enough free RAM to load the GGUF model. Check the status bar — if it's orange, hover for the reason.
- Close other apps, then restart.

**"gemma4:e2b is 7.2 GB — does that fit in 2 GB VRAM?"**
- No. The `eXb` tags are mixture-of-depths models where "effective" params ≠ stored weights. Stick with `gemma3:1b` or `gemma3:4b` on modest hardware.

---

## Development

```bash
flutter analyze    # static analysis
flutter test       # widget + unit tests
flutter run -d windows --debug
```

Project layout:
```
lib/
  models/       · data classes (Message, Conversation, Flashcard, CEFRLevel, …)
  providers/    · ChangeNotifiers (ChatProvider, SettingsProvider, …)
  screens/      · tab roots + their widgets
  services/     · LLMBackend, LLMService, DatabaseService, TTSService, WhisperService, SRSService, CEFRService, …
  widgets/      · reusable UI
scripts/        · Python servers + batch launchers
windows/        · Flutter Windows runner + CMake
bin/windows/llama/  · llama.cpp DLLs (downloaded via fetch_llama_dlls.bat, not in git)
```

### Rebuilding llama.cpp DLLs from source
The prebuilt DLLs on the Releases page are built with `GGML_BACKEND_DL=OFF` so that `llama_cpp_dart`'s single-library FFI loader finds all symbols in one place. If you want to rebuild them for a newer llama.cpp:

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=OFF
cmake --build build --config Release -j
# copy build/bin/*.dll → zaban/bin/windows/llama/
```

---

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

- [llama.cpp](https://github.com/ggerganov/llama.cpp) — underlying inference engine
- [Ollama](https://ollama.ai) — drop-in LLM server
- [Whisper](https://github.com/openai/whisper) / [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — speech recognition
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) — text-to-speech
- [flutter_gemma](https://pub.dev/packages/flutter_gemma), [llama_cpp_dart](https://pub.dev/packages/llama_cpp_dart) — Flutter FFI bridges
