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
      tmux nano less file jq zstd git ca-certificates \
      python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Only the compiled llama.cpp programs and their shared libraries
COPY --from=llama /app/llama* /app/*.so* /app/

# SSH logins don't inherit the image's ENV, so make everything work without it:
# binaries on the default PATH, libs registered with the loader, env via PAM/profile.
RUN ln -sf /app/llama* /usr/local/bin/ \
 && printf '/app\n/usr/local/nvidia/lib64\n/usr/local/nvidia/lib\n' > /etc/ld.so.conf.d/00-llmbox.conf \
 && ldconfig \
 && printf 'OLLAMA_MODELS=/workspace/ollama-models\nOLLAMA_HOST=127.0.0.1:11434\nHF_HOME=/workspace/hf-cache\nHF_XET_HIGH_PERFORMANCE=1\n' >> /etc/environment \
 && printf 'export OLLAMA_MODELS=/workspace/ollama-models OLLAMA_HOST=127.0.0.1:11434 HF_HOME=/workspace/hf-cache HF_XET_HIGH_PERFORMANCE=1\n' > /etc/profile.d/llmbox.sh

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
 && llama-server --version \
 && ls /app/libggml-cuda*.so* >/dev/null \
 && for f in /app/libggml-cuda*.so*; do \
      missing=$(ldd "$f" | grep "not found" | grep -v "libcuda.so" || true); \
      if [ -n "$missing" ]; then echo "CUDA backend missing libs (CUDA version mismatch?):"; echo "$missing"; exit 1; fi; \
    done

# EcoHash's boot command runs a bare `/usr/sbin/sshd`, but only prepares
# /run/sshd and host keys when OpenSSH is missing. Wrap sshd so it always
# prepares them itself (host keys are generated per container, not baked in).
RUN dpkg-divert --local --rename --add /usr/sbin/sshd \
 && printf '#!/bin/sh\nmkdir -p /run/sshd\nssh-keygen -A >/dev/null 2>&1\nexec /usr/sbin/sshd.distrib "$@"\n' > /usr/sbin/sshd \
 && chmod 755 /usr/sbin/sshd \
 && printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config.d/00-llmbox.conf \
 && /usr/sbin/sshd -t && rm -f /etc/ssh/ssh_host_*

WORKDIR /workspace
EXPOSE 8080 11434 22
ENTRYPOINT ["/usr/local/bin/start.sh"]
