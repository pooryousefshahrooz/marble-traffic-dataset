#!/usr/bin/env bash
# One-time setup for a fresh Linux machine: installs Docker, Ollama, a
# Python 3.11 venv with all deps, generates the TLS proxy cert, and grants
# the tcpdump binary raw-capture capability so it can run without sudo.
#
# Works with or without sudo access. Steps that need root are attempted
# with a non-interactive sudo check first (so this never hangs on a
# password prompt) and skipped with clear instructions if unavailable --
# most GPU/shared servers already have Docker, tcpdump, etc. preinstalled
# by an admin, so this is usually a non-issue in practice.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

HAVE_SUDO=0
if sudo -n true 2>/dev/null; then
    HAVE_SUDO=1
fi
ADMIN_TODO=()

run_sudo() {
    # Run a root-needing step only if passwordless sudo is available;
    # otherwise skip it (never blocks on a password prompt).
    if [[ "$HAVE_SUDO" == "1" ]]; then
        sudo "$@"
        return $?
    else
        return 1
    fi
}

echo "=== [1/6] system packages ==="
if [[ "$HAVE_SUDO" == "1" ]]; then
    sudo apt-get update -y
    sudo apt-get install -y tcpdump openssl curl ca-certificates gnupg lsb-release libcap2-bin
else
    echo "no passwordless sudo -- skipping apt-get, assuming tcpdump/openssl/curl are preinstalled"
    for bin in tcpdump openssl curl; do
        command -v "$bin" &>/dev/null || echo "  WARNING: $bin not found and cannot be installed without sudo"
    done
fi

echo "=== [2/6] Docker ==="
if command -v docker &>/dev/null && docker ps &>/dev/null; then
    echo "Docker already installed and usable, skipping."
elif [[ "$HAVE_SUDO" == "1" ]]; then
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | sudo sh
    fi
    sudo usermod -aG docker "$USER"
    echo "Docker installed. You may need to log out/in for group membership to apply."
else
    echo "no passwordless sudo and Docker isn't usable -- the 'database' task category"
    echo "(which needs Docker) will fail until this is fixed. Skipping for now."
    ADMIN_TODO+=("install Docker and add $USER to the 'docker' group (or enable rootless Docker)")
fi

echo "=== [3/6] Ollama + model pull ==="
if ! command -v ollama &>/dev/null; then
    if [[ "$HAVE_SUDO" == "1" ]]; then
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "no passwordless sudo -- ollama's installer needs root. If ollama isn't"
        echo "already installed by an admin, ask them to run: curl -fsSL https://ollama.com/install.sh | sh"
        ADMIN_TODO+=("install ollama (curl -fsSL https://ollama.com/install.sh | sh)")
    fi
else
    echo "Ollama already installed, skipping."
fi
if command -v ollama &>/dev/null; then
    if ! curl -s http://127.0.0.1:11434 >/dev/null 2>&1; then
        nohup ollama serve > /tmp/ollama_serve.log 2>&1 &
        sleep 3
    fi
    ollama pull llama3.2:3b
fi

echo "=== [4/6] Python 3.11 venv ==="
PY=""
for cand in python3.11 python3.10 python3.9; do
    if command -v "$cand" &>/dev/null; then PY="$cand"; break; fi
done
if [[ -z "$PY" ]]; then
    if [[ "$HAVE_SUDO" == "1" ]]; then
        echo "No system python3.9-3.11 found; installing python3.11 via apt..."
        sudo apt-get install -y python3.11 python3.11-venv python3.11-dev || true
        command -v python3.11 &>/dev/null && PY="python3.11"
    fi
    if [[ -z "$PY" ]]; then
        echo "No sudo / apt install of python3.11 unavailable -- falling back to a portable build (no root needed)."
        curl -fsSL -o /tmp/cpython.tar.gz \
            "https://github.com/astral-sh/python-build-standalone/releases/download/20250106/cpython-3.11.11+20250106-x86_64-unknown-linux-gnu-install_only.tar.gz"
        mkdir -p .pyruntime && tar -xzf /tmp/cpython.tar.gz -C .pyruntime
        PY="$HERE/.pyruntime/python/bin/python3.11"
    fi
fi

"$PY" -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install -e .

echo "=== [5/6] TLS proxy cert ==="
bash scripts/generate_certs.sh

echo "=== [6/6] tcpdump without sudo (setcap) ==="
TCPDUMP_BIN="$(command -v tcpdump || true)"
if [[ -z "$TCPDUMP_BIN" ]]; then
    echo "tcpdump not found -- cannot capture traffic until it's installed."
    ADMIN_TODO+=("install tcpdump")
elif command -v getcap &>/dev/null && getcap "$TCPDUMP_BIN" 2>/dev/null | grep -q cap_net_raw; then
    echo "$TCPDUMP_BIN already has cap_net_raw -- no sudo needed to capture."
elif [[ "$HAVE_SUDO" == "1" ]]; then
    sudo setcap cap_net_raw,cap_net_admin+eip "$TCPDUMP_BIN"
    echo "granted cap_net_raw to $TCPDUMP_BIN -- capture works without sudo from now on."
else
    echo "no passwordless sudo -- cannot grant tcpdump capture capability myself."
    ADMIN_TODO+=("run once, as root: setcap cap_net_raw,cap_net_admin+eip $TCPDUMP_BIN")
fi

echo ""
echo "=== setup complete ==="
if [[ ${#ADMIN_TODO[@]} -gt 0 ]]; then
    echo ""
    echo "Some steps need root and no passwordless sudo was available. Ask your"
    echo "server admin to run the following ONE TIME, then re-run ./setup.sh:"
    for item in "${ADMIN_TODO[@]}"; do
        echo "  - $item"
    done
fi
echo ""
echo "next: source .venv/bin/activate && ./run_full_dataset.sh"
