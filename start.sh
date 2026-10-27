#!/usr/bin/env bash
# Container entrypoint: starts no models. Prepares folders, runs sshd,
# and keeps the container alive.
#
# SSH:
#   - sshd always runs, listening on ports 22 and 10000 (override: SSH_PORTS="2222 10000")
#   - Key-only login as root. Your key is picked up from any of these env vars:
#       PUBLIC_KEY, SSH_PUBLIC_KEY, SSH_PUBKEY, PUBKEY, AUTHORIZED_KEYS
#     or from a key the platform writes to /root/.ssh/authorized_keys itself.
set -u
mkdir -p /workspace/logs "${OLLAMA_MODELS:-/workspace/ollama-models}" "${HF_HOME:-/workspace/hf-cache}"

# --- collect SSH keys ---
mkdir -p /root/.ssh /run/sshd
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
for var in PUBLIC_KEY SSH_PUBLIC_KEY SSH_PUBKEY PUBKEY AUTHORIZED_KEYS; do
    key="${!var:-}"
    if [[ -n "$key" ]] && ! grep -qF "$key" /root/.ssh/authorized_keys; then
        printf '%s\n' "$key" >> /root/.ssh/authorized_keys
        echo "[start] added SSH key from \$$var"
    fi
done
chmod 600 /root/.ssh/authorized_keys

# --- start sshd ---
ssh-keygen -A >/dev/null 2>&1
PORT_ARGS=""
for p in ${SSH_PORTS:-22 10000}; do PORT_ARGS="$PORT_ARGS -p $p"; done
# shellcheck disable=SC2086
/usr/sbin/sshd $PORT_ARGS \
    -o PasswordAuthentication=no \
    -o PermitRootLogin=prohibit-password \
    -o PubkeyAuthentication=yes \
    -E /workspace/logs/sshd.log \
  && echo "[start] sshd listening on ports: ${SSH_PORTS:-22 10000}"

if [[ $# -gt 0 ]]; then exec "$@"; else exec sleep infinity; fi
