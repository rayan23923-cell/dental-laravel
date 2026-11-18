# syntax=docker/dockerfile:1
# Piper text-to-speech for calling names on the waiting screen (2026-11-17).
# The MIT build of Piper (2023.11.14-2, no Python needed for synthesis) with
# the Arabic voices of deploy/voices/voices.json (default «دي»), behind a
# tiny HTTP wrapper on port 5000 that only the app container reaches. It
# works only while a sentence is being made.

# The voices: downloaded and made loadable by Piper's onnxruntime (IR 8).
FROM python:3.12-slim AS voices
RUN pip install --no-cache-dir onnx
COPY deploy/voices /src
RUN python3 /src/fetch-voices.py /voices

FROM debian:bookworm-slim
ARG PIPER_VERSION=2023.11.14-2
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 \
    && rm -rf /var/lib/apt/lists/*
RUN arch="$(uname -m)"; case "$arch" in aarch64|arm64) arch=aarch64 ;; *) arch=x86_64 ;; esac \
    && curl -fsSL --retry 5 "https://github.com/rhasspy/piper/releases/download/${PIPER_VERSION}/piper_linux_${arch}.tar.gz" | tar xz -C /opt
COPY --from=voices /voices /opt/voices
# Every voice must speak before the image is used.
RUN for model in /opt/voices/*.onnx; do \
        echo 'المريض أحمد علي' | /opt/piper/piper --model "$model" --output_file /tmp/check.wav \
        && test "$(stat -c %s /tmp/check.wav)" -gt 10000 && rm /tmp/check.wav || exit 1; \
    done
COPY deploy/vps/tts/server.py /opt/server.py
USER nobody
EXPOSE 5000
CMD ["python3", "/opt/server.py"]
