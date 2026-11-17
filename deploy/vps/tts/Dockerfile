# syntax=docker/dockerfile:1
# Piper text-to-speech for calling names on the waiting screen (2026-11-17).
# The MIT build of Piper (2023.11.14-2, no Python needed for synthesis) with
# the Arabic voice «كريم», behind a tiny HTTP wrapper on port 5000 that only
# the app container reaches. It works only while a sentence is being made.
FROM debian:bookworm-slim
ARG PIPER_VERSION=2023.11.14-2
ARG VOICE_URL=https://huggingface.co/rhasspy/piper-voices/resolve/main/ar/ar_JO/kareem/medium
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 \
    && rm -rf /var/lib/apt/lists/*
RUN arch="$(uname -m)"; case "$arch" in aarch64|arm64) arch=aarch64 ;; *) arch=x86_64 ;; esac \
    && curl -fsSL --retry 5 "https://github.com/rhasspy/piper/releases/download/${PIPER_VERSION}/piper_linux_${arch}.tar.gz" | tar xz -C /opt \
    && mkdir -p /opt/voices \
    && curl -fsSL --retry 5 -o /opt/voices/ar_JO-kareem-medium.onnx "${VOICE_URL}/ar_JO-kareem-medium.onnx" \
    && curl -fsSL --retry 5 -o /opt/voices/ar_JO-kareem-medium.onnx.json "${VOICE_URL}/ar_JO-kareem-medium.onnx.json" \
    && echo 'المريض أحمد علي' | /opt/piper/piper --model /opt/voices/ar_JO-kareem-medium.onnx --output_file /tmp/check.wav \
    && test "$(stat -c %s /tmp/check.wav)" -gt 10000 && rm /tmp/check.wav
COPY deploy/vps/tts/server.py /opt/server.py
USER nobody
EXPOSE 5000
CMD ["python3", "/opt/server.py"]
