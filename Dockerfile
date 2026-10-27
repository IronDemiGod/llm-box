# llm-box: llama.cpp (CUDA, Blackwell sm_120) + Ollama + HF CLI + utilities
# Build:  docker build -t <you>/llm-box:latest .
# Pick a CUDA version your host driver supports (nvidia-smi "CUDA Version" >= this).
ARG CUDA_VERSION=12.9.1
ARG UBUNTU=ubuntu24.04

############################ build stage ############################
FROM nvidia/cuda:${CUDA_VERSION}-devel-${UBUNTU} AS build
ARG LLAMA_REF=master
ARG CUDA_ARCH=120
ARG FA_ALL_QUANTS=ON

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git cmake build-essential libcurl4-openssl-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch ${LLAMA_REF} https://github.com/ggml-org/llama.cpp .

# No GPU is needed at build time; link against the CUDA driver stub.
RUN cmake -B build \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
      -DGGML_CUDA_FA_ALL_QUANTS=${FA_ALL_QUANTS} \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_BUILD_TESTS=OFF \
      -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined \
 && cmake --build build --config Release -j"$(nproc)" \
 && cmake --install build --prefix /opt/llama

########################### runtime stage ###########################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-${UBUNTU}

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/opt/llama/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/llama/lib:${LD_LIBRARY_PATH} \
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
      libcurl4 libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# Hugging Face CLI (with fast Xet downloads) + gguf tools
RUN pip install --no-cache-dir --break-system-packages \
      "huggingface_hub[hf_xet,cli]" gguf

# Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh || true \
 && command -v ollama

# llama.cpp binaries + libs
COPY --from=build /opt/llama /opt/llama

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh && mkdir -p /workspace

WORKDIR /workspace
EXPOSE 8080 11434 22
ENTRYPOINT ["/usr/local/bin/start.sh"]
