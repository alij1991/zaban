"""Minimal Kokoro TTS server — OpenAI-compatible /v1/audio/speech endpoint.

Usage: python scripts/kokoro_tts_server.py [--port 8880] [--voice af_heart]

Runs a local HTTP server that accepts text and returns synthesized WAV audio.
"""

import argparse
import io
import json
import struct
import wave
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

parser = argparse.ArgumentParser(description="Kokoro TTS Server")
parser.add_argument("--port", type=int, default=8880, help="Port to listen on")
parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
parser.add_argument("--voice", default="af_heart", help="Default voice")
parser.add_argument("--lang", default="a", help="Language code: a=American English")
parser.add_argument("--device", default="auto", choices=["auto", "cuda", "cpu"],
                    help="Inference device. 'auto' uses CUDA if available.")
args = parser.parse_args()

print(f"Loading Kokoro TTS model (this may download weights on first run)...")
try:
    from kokoro import KPipeline
    import numpy as np
    import torch

    # Device selection. Kokoro is 82M params — tiny — so even a 2GB GPU
    # (MX150) fits it with room to spare. GPU ~6x faster than CPU for this
    # model size.
    if args.device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        device = args.device
        if device == "cuda" and not torch.cuda.is_available():
            print(f"  [!] --device cuda requested but CUDA unavailable, falling back to CPU")
            device = "cpu"

    if device == "cuda":
        gpu_name = torch.cuda.get_device_name(0)
        gpu_mem_gb = torch.cuda.get_device_properties(0).total_memory / (1024**3)
        print(f"  Using GPU: {gpu_name} ({gpu_mem_gb:.1f} GB VRAM)")
    else:
        print(f"  Using CPU. For ~6x speedup on supported GPUs, reinstall torch with CUDA:")
        print(f"    pip uninstall -y torch && pip install torch --index-url https://download.pytorch.org/whl/cu121")

    pipeline = KPipeline(lang_code=args.lang, device=device)
    print(f"Kokoro TTS loaded. Default voice: {args.voice}")
except Exception as e:
    print(f"Failed to load Kokoro: {e}")
    print("Install with: pip install kokoro soundfile numpy torch")
    exit(1)


# Kokoro's KPipeline wraps a PyTorch model; concurrent inference on the same
# model can corrupt intermediate state. Serialize the actual synthesis call.
# ThreadingHTTPServer still helps: request reading and response writing happen
# concurrently, and queued requests start synthesizing the moment the lock is
# released (no accept-loop head-of-line blocking).
_synth_lock = threading.Lock()


SAMPLE_RATE = 24000


def _wav_header(data_size: int) -> bytes:
    """Build a 44-byte WAV header. Pass 0xFFFFFFFF for unknown size (streaming)."""
    # PCM 16-bit mono at SAMPLE_RATE
    byte_rate = SAMPLE_RATE * 1 * 2
    block_align = 1 * 2
    riff_size = 0xFFFFFFFF if data_size == 0xFFFFFFFF else 36 + data_size
    return (
        b"RIFF" + struct.pack("<I", riff_size) + b"WAVE"
        + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, byte_rate, block_align, 16)
        + b"data" + struct.pack("<I", data_size)
    )


def synthesize_to_wav(text: str, voice: str = "af_heart") -> bytes:
    """Generate complete WAV audio bytes from text using Kokoro (buffered)."""
    with _synth_lock:
        audio_chunks = []
        for result in pipeline(text, voice=voice):
            audio_chunks.append(result.audio.numpy())

    if not audio_chunks:
        return b""

    audio = np.concatenate(audio_chunks)
    pcm = (audio * 32767).clip(-32768, 32767).astype(np.int16)
    return _wav_header(len(pcm.tobytes())) + pcm.tobytes()


def stream_synth_chunks(text: str, voice: str, write_bytes):
    """Synthesize text and call write_bytes(chunk) for each WAV-ready PCM chunk.
    Writes the WAV header first (with sentinel size), then raw PCM as each
    Kokoro chunk comes off the pipeline. Holds the synth lock only while
    actively generating — network I/O interleaves with next request's synth.
    """
    # Sentinel header so clients can parse the file before we know total size.
    # miniaudio / ffmpeg / most players accept 0xFFFFFFFF as "unknown" and read
    # until EOF.
    write_bytes(_wav_header(0xFFFFFFFF))

    with _synth_lock:
        for result in pipeline(text, voice=voice):
            audio = result.audio.numpy()
            pcm = (audio * 32767).clip(-32768, 32767).astype(np.int16)
            write_bytes(pcm.tobytes())


class TTSHandler(BaseHTTPRequestHandler):
    # Chunked transfer encoding is HTTP/1.1 only. Without this override,
    # BaseHTTPRequestHandler defaults to HTTP/1.0 and the chunked streaming
    # response becomes malformed — clients abort mid-stream (WinError 10053
    # on the server side), forcing every request to retry against the
    # buffered /synthesize fallback.
    protocol_version = "HTTP/1.1"

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

        stream = bool(data.get("stream", True))
        t0 = time.monotonic()
        print(f"[TTS] Synthesizing{' (stream)' if stream else ''}: {text[:60]}{'...' if len(text) > 60 else ''}")

        try:
            if stream:
                # Chunked transfer: headers now, PCM as Kokoro produces chunks.
                # First audio leaves the server as soon as the first chunk is
                # synth'd, instead of after the whole utterance completes.
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Transfer-Encoding", "chunked")
                self.send_header("X-Accel-Buffering", "no")
                # Close after streaming — BaseHTTPServer's keep-alive handling
                # around chunked responses is unreliable; closing is cheap here.
                self.send_header("Connection", "close")
                self.close_connection = True
                self.end_headers()

                first_chunk_at = [None]

                def write_chunk(b: bytes):
                    if not b:
                        return
                    if first_chunk_at[0] is None:
                        first_chunk_at[0] = time.monotonic()
                    # HTTP/1.1 chunked framing: <hex-size>\r\n<data>\r\n
                    self.wfile.write(f"{len(b):x}\r\n".encode())
                    self.wfile.write(b)
                    self.wfile.write(b"\r\n")
                    self.wfile.flush()

                stream_synth_chunks(text, voice, write_chunk)
                # Terminator chunk
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
                ttfb = first_chunk_at[0] - t0 if first_chunk_at[0] else 0
                total = time.monotonic() - t0
                print(f"[TTS] Done in {total*1000:.0f}ms (ttfb {ttfb*1000:.0f}ms)")
            else:
                wav_bytes = synthesize_to_wav(text, voice=voice)
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Length", str(len(wav_bytes)))
                self.end_headers()
                self.wfile.write(wav_bytes)
                print(f"[TTS] Done in {(time.monotonic()-t0)*1000:.0f}ms")
        except Exception as e:
            print(f"[TTS] Error: {e}")
            try:
                self._json_response(500, {"error": str(e)})
            except Exception:
                pass  # headers already sent in streaming mode

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
    # Warm the pipeline — first synthesis lazy-loads the voice embedding
    # and vocoder, which otherwise adds ~800ms to the first real request.
    print("Warming TTS pipeline...")
    try:
        synthesize_to_wav(".", voice=args.voice)
        print("  [OK] Pipeline warm.")
    except Exception as e:
        print(f"  [!] Warmup failed (non-fatal): {e}")

    server = ThreadingHTTPServer((args.host, args.port), TTSHandler)
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
