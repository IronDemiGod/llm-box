#!/usr/bin/env bash
# Container entrypoint: starts nothing, just prepares folders and keeps the
# container alive. Run ollama / llama-server yourself when you need them.
#   PUBLIC_KEY="ssh-..."  optional: enable SSH login with this key
set -u
mkdir -p /workspace/logs "${OLLAMA_MODELS:-/workspace/ollama-models}" "${HF_HOME:-/workspace/hf-cache}"

if [[ -n "${PUBLIC_KEY:-}" ]]; then
    mkdir -p /root/.ssh /run/sshd && chmod 700 /root/.ssh
    echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
    ssh-keygen -A >/dev/null 2>&1
    /usr/sbin/sshd -o PasswordAuthentication=no
fi

if [[ $# -gt 0 ]]; then exec "$@"; else exec sleep infinity; fi
