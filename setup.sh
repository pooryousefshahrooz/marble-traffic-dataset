#!/usr/bin/env bash
# One-time setup for a fresh Linux machine: installs Docker, Ollama, a
# Python 3.11 venv with all deps, generates the TLS proxy cert, and grants
# passwordless sudo for tcpdump (needed for the traffic-capture pipeline
# to run unattended). Run once, then use ./run_full_dataset.sh.
#
# Tested target: Ubuntu 22.04/24.04. Requires sudo.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "=== [1/6] system packages ==="
sudo apt-get update -y
sudo apt-get install -y tcpdump openssl curl ca-certificates gnupg lsb-release

echo "=== [2/6] Docker ==="
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    echo "Docker installed. You may need to log out/in for group membership to apply."
else
    echo "Docker already installed, skipping."
fi

echo "=== [3/6] Ollama + model pull ==="
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama already installed, skipping."
fi
# Start the daemon if it isn't already running (systemd unit installed by
# the script above normally handles this, but don't assume).
if ! curl -s http://127.0.0.1:11434 >/dev/null 2>&1; then
    nohup ollama serve > /tmp/ollama_serve.log 2>&1 &
    sleep 3
fi
ollama pull llama3.2:3b

echo "=== [4/6] Python 3.11 venv ==="
PY=""
for cand in python3.11 python3.10 python3.9; do
    if command -v "$cand" &>/dev/null; then PY="$cand"; break; fi
done
if [[ -z "$PY" ]]; then
    echo "No system python3.9-3.11 found; installing python3.11 via apt..."
    sudo apt-get install -y python3.11 python3.11-venv python3.11-dev || {
        echo "apt install of python3.11 failed -- falling back to a portable build."
        curl -fsSL -o /tmp/cpython.tar.gz \
            "https://github.com/astral-sh/python-build-standalone/releases/download/20250106/cpython-3.11.11+20250106-x86_64-unknown-linux-gnu-install_only.tar.gz"
        mkdir -p .pyruntime && tar -xzf /tmp/cpython.tar.gz -C .pyruntime
        PY="$HERE/.pyruntime/python/bin/python3.11"
    }
    [[ -z "$PY" ]] && PY="python3.11"
fi

"$PY" -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install -e .

echo "=== [5/6] TLS proxy cert ==="
bash scripts/generate_certs.sh

echo "=== [6/6] passwordless sudo for tcpdump ==="
TCPDUMP_BIN="$(command -v tcpdump)"
SUDOERS_LINE="$USER ALL=(root) NOPASSWD: $TCPDUMP_BIN"
SUDOERS_FILE="/etc/sudoers.d/marble-tcpdump"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    sudo visudo -c -f "$SUDOERS_FILE"
    echo "granted passwordless sudo for $TCPDUMP_BIN"
else
    echo "sudoers rule already exists at $SUDOERS_FILE, skipping"
fi

echo ""
echo "=== setup complete ==="
echo "next: source .venv/bin/activate && ./run_full_dataset.sh"
