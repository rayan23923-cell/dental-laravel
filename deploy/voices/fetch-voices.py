"""Downloads the waiting screen's Piper voices into DEST as <id>.onnx and
<id>.onnx.json (2026-11-17). Models saved with ONNX IR 9 are lowered to IR 8
(their operators are unchanged), so the MIT Piper build 2023.11.14-2, whose
onnxruntime is 1.14, can load them. Needs: pip install onnx.

Usage: python3 fetch-voices.py DEST
"""
import json
import os
import sys
import time
import urllib.request

import onnx

HERE = os.path.dirname(os.path.abspath(__file__))


def fetch(url, path):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=120) as r, open(path + ".part", "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            os.replace(path + ".part", path)
            return
        except Exception as e:  # retry flaky downloads
            print(f"retry {attempt + 1} {url}: {e}", flush=True)
            time.sleep(10)
    raise SystemExit(f"download failed: {url}")


def main(dest):
    os.makedirs(dest, exist_ok=True)
    with open(os.path.join(HERE, "voices.json"), encoding="utf-8") as f:
        voices = {k: v for k, v in json.load(f).items() if not k.startswith("_")}
    for name, src in voices.items():
        model = os.path.join(dest, name + ".onnx")
        fetch(src["onnx"], model)
        fetch(src["json"], model + ".json")
        proto = onnx.load(model)
        if proto.ir_version > 8:
            proto.ir_version = 8
            onnx.save(proto, model)
        size = os.path.getsize(model)
        assert size > 10_000_000, f"{name}: model too small ({size})"
        print(f"{name}: {size // 1_000_000} MB", flush=True)


if __name__ == "__main__":
    main(sys.argv[1])
