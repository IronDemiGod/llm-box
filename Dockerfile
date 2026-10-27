# llm-box (slim): prebuilt llama.cpp binaries on a plain CUDA runtime base.
# Drops the Python/PyTorch conversion stack from llama.cpp's full image.
# Ollama is optional:  docker build --build-arg WITH_OLLAMA=1 ...
ARG CUDA_VERSION=12.8.1

# Official prebuilt llama.cpp (Ubuntu 24.04, CUDA 12.8, Blackwell included)
FROM ghcr.io/ggml-org/llama.cpp:full-cuda AS llama

FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu24.04
ARG WITH_OLLAMA=0

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/app:${PATH} \
    LD_LIBRARY_PATH=/app:${LD_LIBRARY_PATH} \
    OLLAMA_MODELS=/workspace/ollama-models \
    OLLAMA_HOST=127.0.0.1:11434 \
    HF_HOME=/workspace/hf-cache \
    HF_XET_HIGH_PERFORMANCE=1

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

RUN apt-get update && apt-get install -y --no-install-recommends \
      libgomp1 libcurl4 \
      pciutils procps psmisc htop lsof \
      iproute2 iputils-ping curl wget rsync openssh-server \
      tmux nano less file jq zstd ca-certificates \
      python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Only the compiled llama.cpp programs and their shared libraries
COPY --from=llama /app/llama-* /app/*.so* /app/

# Hugging Face CLI + gguf (small; no PyTorch)
RUN pip install --no-cache-dir --break-system-packages \
      "huggingface_hub[hf_xet,cli]" gguf

RUN if [ "$WITH_OLLAMA" = "1" ]; then \
      (curl -fsSL https://ollama.com/install.sh | sh || true) && command -v ollama; \
    fi

COPY start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh \
 && chmod +x /usr/local/bin/start.sh \
 && mkdir -p /workspace \
 && llama-server --version

WORKDIR /workspace
EXPOSE 8080 11434 22
ENTRYPOINT ["/usr/local/bin/start.sh"]
