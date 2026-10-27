# llm-box: official prebuilt llama.cpp CUDA image + Ollama + HF CLI + utilities
# Base: Ubuntu 24.04, CUDA 12.8, llama.cpp binaries in /app (Blackwell sm_120 included)
FROM ghcr.io/ggml-org/llama.cpp:full-cuda

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/app:${PATH} \
    LD_LIBRARY_PATH=/app:${LD_LIBRARY_PATH} \
    OLLAMA_MODELS=/workspace/ollama-models \
    OLLAMA_HOST=127.0.0.1:11434 \
    HF_HOME=/workspace/hf-cache \
    HF_XET_HIGH_PERFORMANCE=1

# Stop package scripts from trying to start services (no systemd in containers)
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

RUN apt-get update && apt-get install -y --no-install-recommends \
      pciutils usbutils lshw dmidecode \
      procps psmisc htop sysstat lsof \
      iproute2 iputils-ping net-tools dnsutils curl wget rsync \
      openssh-server openssh-client \
      tmux screen nano vim less file tree jq \
      zstd xz-utils unzip zip ca-certificates \
      git python3 python3-pip python3-venv \
 && rm -rf /var/lib/apt/lists/*

# Hugging Face CLI (fast Xet downloads) + gguf tools
RUN pip install --no-cache-dir --break-system-packages \
      "huggingface_hub[hf_xet,cli]" gguf

# Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh || true \
 && command -v ollama

COPY start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh \
 && chmod +x /usr/local/bin/start.sh \
 && mkdir -p /workspace

WORKDIR /workspace
EXPOSE 8080 11434 22
ENTRYPOINT ["/usr/local/bin/start.sh"]
