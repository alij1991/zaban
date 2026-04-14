"""Minimal Kokoro TTS server — OpenAI-compatible /v1/audio/speech endpoint.

Usage: python scripts/kokoro_tts_server.py [--port 8880] [--voice af_heart]

Runs a local HTTP server that accepts text and returns synthesized WAV audio.
"""

import argparse
import io
import json
import struct
import wave
from http.server import HTTPServer, BaseHTTPRequestHandler

parser = argparse.ArgumentParser(description="Kokoro TTS Server")
parser.add_argument("--port", type=int, default=8880, help="Port to listen on")
parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
parser.add_argument("--voice", default="af_heart", help="Default voice")
parser.add_argument("--lang", default="a", help="Language code: a=American English")
args = parser.parse_args()

print(f"Loading Kokoro TTS model (this may download weights on first run)...")
try:
    from kokoro import KPipeline
    import numpy as np
    pipeline = KPipeline(lang_code=args.lang)
    print(f"Kokoro TTS loaded. Default voice: {args.voice}")
except Exception as e:
    print(f"Failed to load Kokoro: {e}")
    print("Install with: pip install kokoro soundfile numpy")
    exit(1)


def synthesize_to_wav(text: str, voice: str = "af_heart") -> bytes:
    """Generate WAV audio bytes from text using Kokoro."""
    audio_chunks = []
    for result in pipeline(text, voice=voice):
        audio_chunks.append(result.audio.numpy())

    if not audio_chunks:
        return b""

    audio = np.concatenate(audio_chunks)
    # Convert to 16-bit PCM
    pcm = (audio * 32767).clip(-32768, 32767).astype(np.int16)

    # Write WAV to bytes buffer
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(24000)
        wf.writeframes(pcm.tobytes())
    return buf.getvalue()


class TTSHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/v1/models":
            self._json_response(200, {
                "data": [{"id": "kokoro", "voices": ["af_heart", "af_bella", "am_adam"]}]
            })
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Kokoro TTS Server - OK")

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._json_response(400, {"error": "Invalid JSON"})
            return

        text = data.get("input") or data.get("text") or ""
        voice = data.get("voice", args.voice)

        if not text.strip():
            self._json_response(400, {"error": "No text provided"})
            return

        print(f"[TTS] Synthesizing: {text[:60]}{'...' if len(text) > 60 else ''}")

        try:
            wav_bytes = synthesize_to_wav(text, voice=voice)
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(wav_bytes)))
            self.end_headers()
            self.wfile.write(wav_bytes)
        except Exception as e:
            print(f"[TTS] Error: {e}")
            self._json_response(500, {"error": str(e)})

    def _json_response(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        if "POST" in str(args):
            print(f"[TTS] {args[0]}")


if __name__ == "__main__":
    server = HTTPServer((args.host, args.port), TTSHandler)
    print(f"\nKokoro TTS server listening on http://{args.host}:{args.port}")
    print(f"  POST /v1/audio/speech — synthesize text to audio")
    print(f"  POST /synthesize     — alternative endpoint")
    print(f"  GET  /v1/models      — list voices")
    print(f"\nPress Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        server.server_close()
