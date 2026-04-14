"""Minimal Whisper STT server — OpenAI-compatible /v1/audio/transcriptions endpoint.

Usage: python scripts/whisper_server.py [--port 8000] [--model small]

Runs a local HTTP server that accepts audio files and returns transcriptions
using faster-whisper. Compatible with OpenAI's audio transcription API format.
"""

import argparse
import json
import os
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from io import BytesIO

# Parse command line args early
parser = argparse.ArgumentParser(description="Whisper STT Server")
parser.add_argument("--port", type=int, default=8000, help="Port to listen on")
parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
parser.add_argument("--model", default="small", help="Whisper model size: tiny, base, small, medium, large-v3")
parser.add_argument("--device", default="auto", help="Device: auto, cpu, cuda")
args = parser.parse_args()

print(f"Loading Whisper model '{args.model}' (this may take a moment)...")
from faster_whisper import WhisperModel

device = args.device
if device == "auto":
    try:
        import torch
        device = "cuda" if torch.cuda.is_available() else "cpu"
    except ImportError:
        device = "cpu"

model = WhisperModel(args.model, device=device, compute_type="int8" if device == "cpu" else "float16")
print(f"Model loaded on {device}. Server ready.")


class WhisperHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Health check / model list."""
        if self.path == "/v1/models":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "data": [{"id": args.model, "object": "model"}]
            }).encode())
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Whisper STT Server - OK")

    def do_POST(self):
        """Transcribe audio file."""
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        # Parse multipart form data to extract audio file
        audio_data = self._extract_audio(body)
        if audio_data is None:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "No audio file found"}).encode())
            return

        # Write to temp file and transcribe
        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                f.write(audio_data)
                temp_path = f.name

            segments, info = model.transcribe(temp_path, language="en")
            text = " ".join(segment.text for segment in segments).strip()

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
        """Extract audio bytes from multipart form data."""
        content_type = self.headers.get("Content-Type", "")

        if "multipart/form-data" in content_type:
            # Find boundary
            boundary = content_type.split("boundary=")[-1].strip()
            parts = body.split(f"--{boundary}".encode())
            for part in parts:
                if b"filename=" in part:
                    # Split headers from body
                    header_end = part.find(b"\r\n\r\n")
                    if header_end != -1:
                        return part[header_end + 4:].rstrip(b"\r\n--")
        elif content_type in ("audio/wav", "audio/wave", "application/octet-stream"):
            return body

        return body if len(body) > 100 else None

    def log_message(self, format, *args):
        """Quieter logging — only show transcription results."""
        if "POST" in str(args):
            print(f"[STT] {args[0]}")


if __name__ == "__main__":
    server = HTTPServer((args.host, args.port), WhisperHandler)
    print(f"\nWhisper STT server listening on http://{args.host}:{args.port}")
    print(f"  POST /v1/audio/transcriptions — transcribe audio")
    print(f"  GET  /v1/models — list models")
    print(f"\nPress Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        server.server_close()
