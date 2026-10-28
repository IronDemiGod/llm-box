# llm-box: llama.cpp built for GLM-5.3-Flash (glm5next) GGUFs + HF CLI + tools
#
# orcarouter/GLM-5.3-Flash-Uncensored-GGUF was converted with the PR #27754 branch,
# whose architecture name is "glm5next". Mainline llama.cpp later merged it under the
# name "glm5-next", so mainline/prebuilt builds reject these files. We therefore build
# the exact PR branch (pinned commit) for Blackwell (sm_120).
ARG CUDA_VERSION=12.8.1

############################ build stage ############################
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04 AS build
ARG LLAMA_REPO=https://github.com/unslothai/llama.cpp
ARG LLAMA_COMMIT=86ebfef2c6a0f3359a2a07d2c215d61b0fa885c9
ARG CUDA_ARCH=120

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git cmake build-essential libcurl4-openssl-dev libssl-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git init -q . && git remote add origin ${LLAMA_REPO} \
 && git fetch -q --depth 1 origin ${LLAMA_COMMIT} && git checkout -q FETCH_HEAD

# No GPU needed at build time; link against the CUDA driver stub.
RUN cmake -B build \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLAMA_BUILD_TESTS=OFF \
      -DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined \
 && cmake --build build --config Release -j"$(nproc)" \
      --target llama-server llama-cli llama-mtmd-cli llama-gguf-split llama-quantize llama-bench \
 && mkdir -p /app \
 && cp build/bin/llama-* /app/ \
 && find build -name "*.so*" -exec cp -P {} /app/ \;

########################### runtime stage ###########################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/app:${PATH} \
    LD_LIBRARY_PATH=/app:${LD_LIBRARY_PATH} \
    HF_HOME=/workspace/hf-cache \
    HF_XET_HIGH_PERFORMANCE=1

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

RUN apt-get update && apt-get install -y --no-install-recommends \
      libgomp1 libcurl4 libssl3 \
      pciutils procps psmisc htop lsof \
      iproute2 iputils-ping curl wget rsync openssh-server \
      tmux nano less file jq zstd git ca-certificates \
      python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /app /app

# SSH logins don't inherit the image's ENV: put binaries on the default PATH,
# register libs with the loader, and set env vars via PAM/profile.
RUN ln -sf /app/llama-* /usr/local/bin/ \
 && printf '/app\n/usr/local/nvidia/lib64\n/usr/local/nvidia/lib\n' > /etc/ld.so.conf.d/00-llmbox.conf \
 && ldconfig \
 && printf 'HF_HOME=/workspace/hf-cache\nHF_XET_HIGH_PERFORMANCE=1\n' >> /etc/environment \
 && printf 'export HF_HOME=/workspace/hf-cache HF_XET_HIGH_PERFORMANCE=1\n' > /etc/profile.d/llmbox.sh

RUN pip install --no-cache-dir --break-system-packages \
      "huggingface_hub[hf_xet,cli]" gguf

COPY start.sh /usr/local/bin/start.sh
RUN sed -i 's/\r$//' /usr/local/bin/start.sh \
 && chmod +x /usr/local/bin/start.sh \
 && mkdir -p /workspace \
 && llama-server --version \
 && ls /app/libggml-cuda*.so* >/dev/null \
 && for f in /app/llama-server /app/libggml-cuda*.so*; do \
      missing=$(ldd "$f" | grep "not found" | grep -v "libcuda.so" || true); \
      if [ -n "$missing" ]; then echo "Missing libs for $f:"; echo "$missing"; exit 1; fi; \
    done

# EcoHash's boot command runs a bare `/usr/sbin/sshd` but only prepares /run/sshd
# and host keys when OpenSSH is missing. Wrap sshd so it always prepares them
# (host keys generated per container, not baked into the public image).
RUN dpkg-divert --local --rename --add /usr/sbin/sshd \
 && printf '#!/bin/sh\nmkdir -p /run/sshd\nssh-keygen -A >/dev/null 2>&1\nexec /usr/sbin/sshd.distrib "$@"\n' > /usr/sbin/sshd \
 && chmod 755 /usr/sbin/sshd \
 && printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config.d/00-llmbox.conf \
 && /usr/sbin/sshd -t && rm -f /etc/ssh/ssh_host_*

WORKDIR /workspace
EXPOSE 8080 22
ENTRYPOINT ["/usr/local/bin/start.sh"]
