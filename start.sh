#!/usr/bin/env bash
# Container entrypoint: starts no models. Prepares folders, runs sshd,
# and keeps the container alive.
#
# SSH:
#   - sshd always runs, listening on port 22 (override: SSH_PORTS="22 2222")
#   - Key-only login as root. Your key is picked up from any of these env vars:
#       SSH_AUTHORIZED_KEYS, PUBLIC_KEY, SSH_PUBLIC_KEY, SSH_PUBKEY, PUBKEY, AUTHORIZED_KEYS
#     or from a key the platform writes to /root/.ssh/authorized_keys itself.
set -u
mkdir -p /workspace/logs "${OLLAMA_MODELS:-/workspace/ollama-models}" "${HF_HOME:-/workspace/hf-cache}"

# --- collect SSH keys ---
mkdir -p /root/.ssh /run/sshd
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
for var in SSH_AUTHORIZED_KEYS PUBLIC_KEY SSH_PUBLIC_KEY SSH_PUBKEY PUBKEY AUTHORIZED_KEYS; do
    key="${!var:-}"
    if [[ -n "$key" ]] && ! grep -qF "$key" /root/.ssh/authorized_keys; then
        printf '%s\n' "$key" >> /root/.ssh/authorized_keys
        echo "[start] added SSH key from \$$var"
    fi
done
chmod 600 /root/.ssh/authorized_keys

# --- start sshd (skip if the platform already started it) ---
if ! pgrep -x sshd >/dev/null && ! pgrep -f sshd.distrib >/dev/null; then
PORT_ARGS=""
for p in ${SSH_PORTS:-22}; do PORT_ARGS="$PORT_ARGS -p $p"; done
# shellcheck disable=SC2086
/usr/sbin/sshd $PORT_ARGS \
    -o PasswordAuthentication=no \
    -o PermitRootLogin=prohibit-password \
    -o PubkeyAuthentication=yes \
    -E /workspace/logs/sshd.log \
  && echo "[start] sshd listening on ports: ${SSH_PORTS:-22}"
fi

if [[ $# -gt 0 ]]; then exec "$@"; else exec sleep infinity; fi
