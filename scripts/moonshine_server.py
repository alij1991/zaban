"""Minimal Moonshine STT server — OpenAI-compatible /v1/audio/transcriptions endpoint.

Usage: python scripts/moonshine_server.py [--port 8000] [--model moonshine/base]

Runs a local HTTP server that accepts audio files and returns transcriptions
using Useful Sensors' Moonshine (English-only, CPU-optimised, ONNX runtime).

Why Moonshine over Whisper for this app:
- ~10x lower latency on CPU (~100-200ms vs 1-2s for Whisper small)
- 6.65% WER on LibriSpeech clean — competitive with Whisper small (~6%)
- No GPU required; int8 quantised ONNX runs fine on laptop CPUs
- English-only — that's exactly our use case (Persian speakers learning English)

Compatible with Zaban's existing `WhisperTranscriptionService` Dart client
because the HTTP contract is identical (same endpoints, same JSON shape).
"""

import argparse
import json
import os
import tempfile
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

# Parse command line args early
parser = argparse.ArgumentParser(description="Moonshine STT Server")
parser.add_argument("--port", type=int, default=8000, help="Port to listen on")
parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
parser.add_argument(
    "--model",
    default="moonshine/base",
    help="Moonshine model: moonshine/tiny (27M params) or moonshine/base (61M)",
)
args = parser.parse_args()

print(f"Loading Moonshine model '{args.model}' (this may take a moment)...")

# moonshine_onnx ships ONNX-only inference — no torch dependency, smaller install,
# and the quantised weights run comfortably on laptop CPUs. `load_audio` is the
# bundled helper that uses librosa under the hood to resample to 16kHz mono and
# returns a [1, samples] float32 ndarray — exactly what `generate()` expects.
from moonshine_onnx import MoonshineOnnxModel, load_tokenizer, load_audio  # noqa: E402

model = MoonshineOnnxModel(model_name=args.model)
tokenizer = load_tokenizer()

# Warm-up: first inference builds and caches onnxruntime kernels. Without a
# warm-up the first real request pays ~300-800ms of graph-optimisation latency
# on top of the actual transcribe time, which users feel as a visible pause.
try:
    _warm_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..",
        ".venv",
        "Lib",
        "site-packages",
        "moonshine_onnx",
        "assets",
        "beckett.wav",
    )
    if os.path.exists(_warm_path):
        _ = model.generate(load_audio(_warm_path))
        print("Warm-up inference complete.")
except Exception as _e:
    print(f"Warm-up skipped ({_e}); first request will be slower.")

print(f"Model loaded. Server ready.")


def _transcribe_file(path: str) -> str:
    """Load audio → 16kHz mono float32 → Moonshine → text."""
    # load_audio handles arbitrary sample rates / codecs and returns the
    # [1, samples] float32 array Moonshine's encoder expects.
    audio = load_audio(path)
    # Guard: Moonshine only supports 0.1s < clip < 64s. Clips shorter than 0.1s
    # are almost always noise / dropped frames — return empty instead of raising.
    num_samples = audio.shape[-1]
    if num_samples < 1600:  # 0.1s @ 16kHz
        return ""
    if num_samples > 64 * 16000:
        # Trim to 64s ceiling. Chunked long-form transcription would be a
        # separate endpoint; we don't have a caller that records >64s today.
        audio = audio[:, : 64 * 16000]
    tokens = model.generate(audio)
    return tokenizer.decode_batch(tokens)[0].strip()


class MoonshineHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Health check / model list."""
        if self.path == "/v1/models":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(
                json.dumps({"data": [{"id": args.model, "object": "model"}]}).encode()
            )
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Moonshine STT Server - OK")

    def do_POST(self):
        """Transcribe audio file."""
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        audio_data = self._extract_audio(body)
        if audio_data is None:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "No audio file found"}).encode())
            return

        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                f.write(audio_data)
                temp_path = f.name

            text = _transcribe_file(temp_path)

            os.unlink(temp_path)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"text": text}).encode())

        except Exception as e:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def _extract_audio(self, body: bytes) -> bytes | None:
        """Extract audio bytes from multipart form data.

        Kept byte-for-byte compatible with whisper_server.py's parser so the
        Dart `WhisperTranscriptionService` works against either backend
        without any client-side changes.
        """
        content_type = self.headers.get("Content-Type", "")

        if "multipart/form-data" in content_type:
            boundary = content_type.split("boundary=")[-1].strip()
            parts = body.split(f"--{boundary}".encode())
            for part in parts:
                if b"filename=" in part:
                    header_end = part.find(b"\r\n\r\n")
                    if header_end != -1:
                        return part[header_end + 4 :].rstrip(b"\r\n--")
        elif content_type in ("audio/wav", "audio/wave", "application/octet-stream"):
            return body

        return body if len(body) > 100 else None

    def log_message(self, format, *args):
        """Quieter logging — only show transcription results."""
        if "POST" in str(args):
            print(f"[STT] {args[0]}")


if __name__ == "__main__":
    # ThreadingHTTPServer so a slow transcription can't head-of-line-block a
    # parallel health check. onnxruntime releases the GIL during inference,
    # so concurrent requests genuinely parallelise on multi-core CPUs.
    server = ThreadingHTTPServer((args.host, args.port), MoonshineHandler)
    print(f"\nMoonshine STT server listening on http://{args.host}:{args.port}")
    print(f"  POST /v1/audio/transcriptions — transcribe audio")
    print(f"  GET  /v1/models — list models")
    print(f"\nPress Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        server.server_close()
