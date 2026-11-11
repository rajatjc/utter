#!/usr/bin/env python3
"""Utter's local speech-to-text sidecar: Whisper on Apple Silicon via mlx-whisper.

Keeps the model loaded and answers HTTP requests on 127.0.0.1 only, on a port
chosen by the OS (written to --port-file once the model is loaded). When the
UTTER_WHISPER_TOKEN environment variable is set, every request must carry it in
an X-Utter-Token header, so other programs on the Mac can't use the server.

  GET  /health                -> {"status": "ready", "model": "..."}
  POST /transcribe            -> {"text": "...", "seconds": 0.41}
       JSON body: {"path": "/tmp/clip.wav", "language": "en", "prompt": "Acme, Kubernetes"}

Audio must be 16 kHz mono 16-bit PCM WAV (decoded with the wave module, so ffmpeg
isn't needed). Nothing leaves the machine.
"""
import argparse
import hmac
import json
import os
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

import mlx_whisper

MODEL = "mlx-community/whisper-large-v3-turbo"
LOCK = threading.Lock()  # MLX runs are serialized
TOKEN = os.environ.get("UTTER_WHISPER_TOKEN", "")


def read_wav(path):
    with wave.open(path, "rb") as w:
        if w.getframerate() != 16000 or w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise ValueError("expected 16 kHz mono 16-bit WAV")
        frames = w.readframes(w.getnframes())
    return np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0


def transcribe(audio, language=None, prompt=None):
    kwargs = {
        "path_or_hf_repo": MODEL,
        "verbose": None,
        "fp16": True,
        "condition_on_previous_text": False,
    }
    if language:
        kwargs["language"] = language
    if prompt:
        kwargs["initial_prompt"] = prompt
    with LOCK:
        result = mlx_whisper.transcribe(audio, **kwargs)
    segments = result.get("segments", [])
    # Whisper invents text on silence ("Thank you.", "Subtitles by..."); drop
    # segments the model itself thinks are not speech.
    kept = [s["text"] for s in segments if s.get("no_speech_prob", 0) < 0.6]
    return " ".join(t.strip() for t in kept).strip()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # quiet
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        if not TOKEN:
            return True
        if hmac.compare_digest(self.headers.get("X-Utter-Token", ""), TOKEN):
            return True
        self._json(401, {"error": "unauthorized"})
        return False

    def do_GET(self):
        if not self._authorized():
            return
        if self.path == "/health":
            self._json(200, {"status": "ready", "model": MODEL})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if not self._authorized():
            return
        if self.path != "/transcribe":
            return self._json(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            audio = read_wav(body["path"])
            if len(audio) < 16000 * 0.3:
                return self._json(200, {"text": "", "seconds": 0})
            started = time.time()
            text = transcribe(audio, body.get("language"), body.get("prompt"))
            self._json(200, {"text": text, "seconds": round(time.time() - started, 2)})
        except Exception as e:  # report to the app instead of dying
            self._json(500, {"error": str(e)})


def main():
    global MODEL
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=0, help="0 lets the OS pick a free port")
    ap.add_argument("--port-file", help="write the bound port here once ready")
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--parent-pid", type=int, default=0, help="exit when this process goes away")
    args = ap.parse_args()
    MODEL = args.model

    if args.parent_pid:
        def watch_parent():
            while True:
                time.sleep(2)
                if os.getppid() != args.parent_pid:
                    os._exit(0)
        threading.Thread(target=watch_parent, daemon=True).start()

    started = time.time()
    print(f"loading {MODEL} ...", flush=True)
    transcribe(np.zeros(16000, dtype=np.float32), language="en")  # loads and warms the model
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    port = server.server_address[1]
    if args.port_file:
        tmp = args.port_file + ".tmp"
        with open(tmp, "w") as fh:
            fh.write(str(port))
        os.replace(tmp, args.port_file)  # atomic: the app never reads half a file
    print(f"ready in {time.time() - started:.1f}s on 127.0.0.1:{port}"
          f"{' (token required)' if TOKEN else ''}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
